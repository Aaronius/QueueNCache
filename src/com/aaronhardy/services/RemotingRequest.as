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
	import com.aaronhardy.services.errors.QueueError;
	import com.aaronhardy.services.events.QueueEvent;
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.NetStatusEvent;
	import flash.net.NetConnection;
	import flash.net.Responder;
	
	[Event(name="requestComplete", type="flash.events.QueueEvent")]
	[Event(name="requestRetryDurationStarted", type="com.aaronhardy.services.events.QueueEvent")]
	[Event(name="requestRetryDurationEnded", type="com.aaronhardy.services.events.QueueEvent")]
	/**
	 * Abstracts the processing of a remoting request to make it compatible with the ServiceQueue.
	 * @see com.aaronhardy.services.IQueueableRequest
	 */
	public class RemotingRequest extends EventDispatcher implements IQueueableRequest
	{
		protected var gateway:String;
		protected var source:String;
		protected var resultHandler:Function;
		protected var faultHandler:Function;
		protected var serviceParams:Array;
			
		/**
		 * The fault manager used for managing timeouts, HTTP status codes, and retries.
		 */
		protected var faultManager:FaultManager;
		
		/**
		 * Whether to ignore any response coming back from the server.  This is used because
		 * sometimes even when the connection is closed a netstatus event will be dispatched or the 
		 * actual response will still call the  internalResultHandler or internalFaultHandler.  
		 * For example, the data may be all there but not typed appropriately or other "partial" 
		 * behavior.  By setting this flag to true, the handlers can know to ignore 
		 * what comes through. This MAY cause issues if the request is retried before the partial 
		 * response comes through the handlers, but this hasn't happen in tests.  A more appropriate 
		 * measure would be to completely disconnect the handlers from the NetConnection instance 
		 * but this doesn't seem feasible once NetConnection.call() has already been called.
		 */
		protected var ignoreResponse:Boolean = false
		
		/**
		 * The NetConnection instance.  Stored as a class variable so extending classes
		 * can access it if needed.
		 */
		protected var conn:NetConnection;
		
		public function RemotingRequest(
				gateway:String, 
				source:String, 
				resultHandler:Function,	
				faultHandler:Function, 
				serviceParams:Array,
				timeout:Number=0, 
				retryStatusCodes:Array=null,
				retryTimeout:Boolean=true, 
				retryIntervals:Array=null)
		{
			this.gateway = gateway;
			this.source = source;
			this.resultHandler = resultHandler;
			this.faultHandler = faultHandler;
			this.serviceParams = serviceParams;
			
			if ((!isNaN(timeout) && timeout > 0) || 
					(retryStatusCodes && retryStatusCodes.length > 0 && 
					retryIntervals && retryIntervals.length > 0))
			{
				faultManager = new FaultManager(
						timeout, retryStatusCodes, retryTimeout, retryIntervals);
				faultManager.addEventListener(
						QueueEvent.REQUEST_TIMEOUT, 
						faultManager_timeoutHandler);
				faultManager.addEventListener(
						QueueEvent.REQUEST_RETRY_DURATION_STARTED, 
						redispatch);
				faultManager.addEventListener(
						QueueEvent.REQUEST_RETRY_DURATION_ENDED, 
						redispatch);
			}
		}
		
		public function execute():void
		{
			ignoreResponse = false;

			if (faultManager)
			{
				faultManager.startTimeoutTimer();
			}
			
			conn = new NetConnection();
			conn.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler, false, 0 , true);
			conn.connect(gateway);
			// The responder is made up of internal result/fault handlers to ensure we can
			// dispatch an COMPLETE event as required by the ServiceQueue.
			var responder:Responder = new Responder(internalResultHandler, internalFaultHandler);
			var callParams:Array = new Array(source, responder);
			callParams = callParams.concat(serviceParams);
			conn.call.apply(null, callParams);
		}
		
		protected function netStatusHandler(event:NetStatusEvent):void
		{
			if (!ignoreResponse)
			{
				// Timeout is determined by how long it takes for the server to respond.
				// Now that the server has responded, stop the timeout timer.
				if (faultManager)
				{
					faultManager.stop();
				}
				
				// In the case below, a true HTTP error response has been received, but to maintain
				// a central point for error handling, we'll call the internalFaultHandler.  See
				// the internalFaultHandler for more info. 
				if (event.info.level == 'error')
				{
					internalFaultHandler(event);
				}
			}
		}
		
		/**
		 * Ensures we can dispatch a COMPLETE event as required by the ServiceQueue.
		 */
		protected function internalResultHandler(result:*=null):void
		{
			if (!ignoreResponse)
			{
				ignoreResponse = true;
				if (!faultManager || !faultManager.awaitingRetry)
				{
					// If there's a error thrown within the result handler, we still want to make
					// sure finish() is called.  We don't want to call finish() beforehand because
					// of its out-of-order nature.
					try
					{
						resultHandler(result);
					}
					catch (e:Error)
					{
						finish();
						throw e;
					}
					finish();
				}
			}
		}
		
		/**
		 * Ensures we can dispatch a COMPLETE event as required by the ServiceQueue.
		 */
		protected function internalFaultHandler(error:*=null):void
		{
			if (!ignoreResponse)
			{
				ignoreResponse = true;
				
				// Depending on the AMF system used, sometimes failure HTTP status codes will come
				// through a 200-level response.  Rather than the server sending back
				// a true 500 internal server error HTTP response, it will send back a 200 HTTP
				// response and inside the response the data will indicate there was a 500 internal 
				// server error.  In either case, we've fed the response to this point where we'll
				// retreive the HTTPStatusCode.
				if (faultManager && error)
				{
					var statusCode:int = getHTTPStatusCode(error);
					if (statusCode > 0)
					{
						faultManager.handleStatusCode(statusCode);
					}
				}
				
				// If we're awaiting a retry then we don't want to be calling the faulthandler
				// or saying that we've finished.
				if (!faultManager || !faultManager.awaitingRetry)
				{
					// If there's a error thrown within the result handler, we still want to make
					// sure finish() is called.  We don't want to call finish() beforehand because
					// of its out-of-order nature.
					try
					{
						faultHandler(error);
					}
					catch (e:Error)
					{
						finish();
						throw e;
					}
					finish();
				}
			}
		}
		
		/**
		 * Retrieve the HTTP status code from an object.  The object is assumed to have one of 
		 * the structures below, currently (1) object.info.errorCode where errorCode is the
		 * http status code or (2) object.info.description where description has the error code
		 * embedded as "HTTP: Status 500" for example.
		 */
		protected function getHTTPStatusCode(status:*):int
		{
			if (status is Object &&
					Object(status).hasOwnProperty('info') &&  
					Object(status.info).hasOwnProperty('errorCode'))
			{
				return status.info.errorCode;
			}
			else if (status is Object &&
					Object(status).hasOwnProperty('info') &&  
					Object(status.info).hasOwnProperty('description'))
			{
				var pattern:RegExp = /HTTP: Status (\d+)/i;
				var description:String = NetStatusEvent(status).info.description;
				var result:Array = pattern.exec(description);
				if (result && result.length > 1)
				{
					return result[1];
				}
			}
			return 0;
		}
		
		/**
		 * Redispatches any event.
		 */
		protected function redispatch(event:Event):void
		{
			dispatchEvent(event.clone());
		}
		
		/**
		 * Handles when the fault manager notifies of a timeout.
		 */
		protected function faultManager_timeoutHandler(event:QueueEvent):void
		{
			if (faultManager.awaitingRetry)
			{
				ignoreResponse = true;
				try
				{
					conn.close();
				} catch (error:Error) {}
			}
			else
			{
				var errorMessage:String = 'The server took too long to respond to the request. ' +
						'Gateway: ' + gateway + ', Source: ' + source;
				internalFaultHandler(new QueueError(QueueError.TIMEOUT, errorMessage));
			}
		}
		
		public function cancel():void
		{
			// Don't call internalFaultHandler() because it will only call the faultHandler() if
			// the faultManager is not awaiting a retry.
			ignoreResponse = true;
			faultHandler();
			finish();
		}
		
		protected function finish():void
		{
			try
			{
				conn.close();
			} catch (error:Error) {}
			
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
	}
}