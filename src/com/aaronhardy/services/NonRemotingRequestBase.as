// Copyright (c) 2010 Aaron Hardy
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

package com.aaronhardy.services
{
	import com.aaronhardy.services.events.QueueEvent;
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.HTTPStatusEvent;
	import flash.events.IOErrorEvent;
	
	/**
	 * Most non-remoting request wrappers use some common logic.  Rather than duplicating the
	 * logic in each of the request wrappers, they can extend this base class and piggyback
	 * off their commonality.
	 */
	public class NonRemotingRequestBase extends EventDispatcher implements IQueueableRequest
	{
		/**
		 * The fault manager used for managing timeouts, HTTP status codes, and retries.
		 */
		protected var faultManager:FaultManager;
		
		public function NonRemotingRequestBase(
				timeout:Number=0, 
				retryStatusCodes:Array=null,
				retryTimeout:Boolean=true, 
				retryIntervals:Array=null)
		{
			// If timeouts or retries are going to be handled, set up a fault manager.
			if ((!isNaN(timeout) && timeout > 0) || 
					(retryStatusCodes && retryStatusCodes.length > 0 && 
					retryIntervals && retryIntervals.length > 0))
			{
				faultManager = new FaultManager(
						timeout, retryStatusCodes, retryTimeout, retryIntervals);
				faultManager.addEventListener(
						QueueEvent.REQUEST_TIMEOUT, 
						faultManager_timeoutHandler);
				
				// Redispatch duration started and ended events.  These will be originating from the
				// fault manager but the queue will be watching this request for them.
				faultManager.addEventListener(
						QueueEvent.REQUEST_RETRY_DURATION_STARTED, 
						redispatch);
				faultManager.addEventListener(
						QueueEvent.REQUEST_RETRY_DURATION_ENDED, 
						redispatch);
			}
		}
		
		/**
		 * Starts the timeout timer. Should be overridden by the extending request and provide 
		 * functionality for starting the request.  
		 */
		public function execute():void
		{
			if (faultManager)
			{
				faultManager.startTimeoutTimer();
			}
		}
		
		/**
		 * Should be called by the extending request when the HTTP status arrives.  This uses the 
		 * generic HTTPStatusEvent to determine if a retry is needed.
		 */
		protected function httpStatusHandler(event:HTTPStatusEvent):void
		{
			if (faultManager)
			{
				// Timeout is determined by how long it takes for the server to respond.
				// Now that the server has responded, stop the timeout timer.
				faultManager.stop();
				faultManager.handleStatusCode(event.status);
				
				// If the fault manager is awaiting a retry, it means the status code was an
				// eligible retry status code and the request has not hit its max retries.
				// In case outside classes are listening for the event, we'll
				// stop its propagation here.  We want to keep events quiet until all retries
				// are complete.
				if (faultManager.awaitingRetry)
				{
					// Normally we would close the connection here by calling closeConnection()
					// because we don't care about the rest of the response.  However, when the 
					// HTTP status is something like a 500 in which a complete event comes
					// immediately afterward, closing the connection right now ends up creating
					// an error within URLStream later:
					// Error: Error #2029: This URLStream object does not have a stream opened.
					//    at flash.net::URLStream/readBytes()
					//    at flash.net::URLLoader/onComplete()
					// This error occurs even if we wrap the close() call with a try-catch.  It's 
					// thrown due to processing from when the complete event is dispatched, not when 
					// the close() occurs. As you can see by the error, the URLStream object tries 
					// reading bytes when triggered by URLLoader.onComplete(). It appears that 
					// there's no try-catch within URLStream to deal with the case where the 
					// URLLoader is closed and there doesn't seem to be any way to try-catch it.
					// Because of this, we'll pass on closing the connection and let it run its
					// course.
					// closeConnection();
					event.stopImmediatePropagation();
				}
			}
			
			if (!faultManager || !faultManager.awaitingRetry)
			{
				redispatch(event);
			}
		}
		
		/**
		 * Should be called by the extending request when the response arrives.
		 */
		protected function completeHandler(event:Event=null):void
		{
			// If we're awaiting a retry then we don't want to pay attention to anything that
			// comes through here.
			if (!faultManager || !faultManager.awaitingRetry)
			{
				if (event)
				{
					redispatch(event);
				}
				finish();
			}
			else
			{
				// If an event comes from the Loader, URLLoader, etc., we want want to stop the
				// event from continuing propagation because we will be retrying shortly.
				event.stopImmediatePropagation();
			}
		}
		
		/**
		 * Re-dispatches any event.
		 */
		protected function redispatch(event:Event):void
		{
			dispatchEvent(event.clone());
		}
		
		/**
		 * Should be called by the extending request when the request should be canceled.
		 * extending classes should also do what's needed to close out the connection if
		 * one exists. It is very important that this cancel function is called when a request
		 * is to be canceled.  If an outside class has a reference to say, a Loader that this
		 * class wraps and the outside class calls Loader.close directly, this request wrapper
		 * won't know about it and therefore will never be removed from the queue.  From research,
		 * it appears there's no event dispatched from Loader that this class could watch to
		 * determine that the loader has been closed.
		 */
		public function cancel():void
		{
			finish();
		}
		
		/**
		 * Should be overridden by the extending request and provide the ability to close the
		 * connection to the server if one exists.
		 */
		protected function closeConnection():void
		{
			// To be overridden.
		}
		
		/**
		 * Should be overridden by the extending request and provide the request url.
		 */
		protected function getUrl():String
		{
			// To be overridden.
			return null;
		}
		
		/**
		 * Should be overridden by the extending request and provide the ability to remove
		 * event listeners and any final cleanup.  This will only be called after the request has 
		 * been fully completed successfully or unsuccessfully.
		 */
		protected function finish():void
		{
			closeConnection();
			
			// We shouldn't need fault manager from here on out so we'll null it out to make
			// sure it gets cleaned up even if a reference to the request remains.
			if (faultManager)
			{
				faultManager.stop();
				faultManager.removeEventListener(
							QueueEvent.REQUEST_RETRY_DURATION_STARTED, 
							redispatch);
				faultManager.removeEventListener(
							QueueEvent.REQUEST_RETRY_DURATION_ENDED, 
							redispatch);
				faultManager = null;
			}
			
			dispatchEvent(new QueueEvent(QueueEvent.REQUEST_COMPLETE));
		}
		
		/**
		 * Handles when the fault manager notifies of a timeout.
		 */
		protected function faultManager_timeoutHandler(event:QueueEvent):void
		{
			// Attempt to close the connect.  We don't want to continue the loading process
			// for the current request regardless of whether we're going to be retrying.
			closeConnection();
			
			// If the fault manager isn't awaiting a retry, we'll let outside classes know about
			// the timout and that our request is complete.  Notice that a TIMEOUT event is NOT
			// dispatched from this class if we having future retries.
			if (!faultManager.awaitingRetry)
			{
				var errorMessage:String = 'The server took too long to respond to the request.';
				var requestUrl:String = getUrl();
				
				if (requestUrl)
				{
					errorMessage += ' URL: ' + requestUrl;
				}
				
				// While it would be nice to dispatch this IOErrorEvent off the 
				// Loader.contentLoaderInfo, URLLoader, etc in case outside classes are only
				// looking for IOErrorEvents on such classes instead of this request wrapper,
				// flash throws "The LoaderInfo class does not implement this method." when
				// attempting to dispatch events of LoaderInfo.
				dispatchEvent(new IOErrorEvent(IOErrorEvent.IO_ERROR, false, false,	errorMessage));
				finish();
			}
		}
	}
}