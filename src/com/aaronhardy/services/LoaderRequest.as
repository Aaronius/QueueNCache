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
	
	import flash.display.Loader;
	import flash.events.Event;
	import flash.events.HTTPStatusEvent;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.URLRequest;
	import flash.system.LoaderContext;
	
	[Event(name="requestComplete", type="flash.events.QueueEvent")]
	[Event(name="requestRetryDurationStarted", type="com.aaronhardy.services.events.QueueEvent")]
	[Event(name="requestRetryDurationEnded", type="com.aaronhardy.services.events.QueueEvent")]
	[Event(name="complete", type="flash.events.Event")]
	[Event(name="ioError", type="flash.events.IOErrorEvent")]
	[Event(name="securityError", type="flash.events.SecurityErrorEvent")]
	[Event(name="httpStatus", type="flash.events.HTTPStatusEvent")]
	[Event(name="progress", type="flash.events.ProgressEvent")]
	/**
	 * Abstracts the processing of a Loader to make it compatible with the ServiceQueue.
	 * @see com.aaronhardy.services.IQueueableRequest
	 */
	public class LoaderRequest extends NonRemotingRequestBase implements IQueueableRequest
	{
		protected var _loader:Loader;
		
		public function get loader():Loader
		{
			return _loader;
		}
		
		public var request:URLRequest;
		public var context:LoaderContext;
		
		public function LoaderRequest(
				loader:Loader,
				request:URLRequest, 
				context:LoaderContext=null,
				timeout:Number=0, 
				retryStatusCodes:Array=null,
				retryTimeout:Boolean=true, 
				retryIntervals:Array=null)
		{
			this._loader = loader;
			this.request = request;
			this.context = context;
			
			super(timeout, retryStatusCodes, retryTimeout, retryIntervals);
		}
		
		/**
		 * @inheritDoc
		 */
		override public function execute():void
		{
			super.execute();
			loader.contentLoaderInfo.addEventListener(Event.COMPLETE, completeHandler, false, int.MAX_VALUE, true);
			loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, completeHandler, false, int.MAX_VALUE, true);
			loader.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR, completeHandler, false, int.MAX_VALUE, true);
			loader.contentLoaderInfo.addEventListener(HTTPStatusEvent.HTTP_STATUS, httpStatusHandler, false, int.MAX_VALUE, true);
			loader.contentLoaderInfo.addEventListener(ProgressEvent.PROGRESS, redispatch, false, int.MAX_VALUE, true);
			loader.load(request, context);
		}
		
		/**
		 * @inheritDoc
		 */
		override protected function closeConnection():void
		{
			super.closeConnection();
			try
			{
				loader.close();
			} catch (e:Error) {}
		}
		
		/**
		 * @inheritDoc
		 */
		override protected function finish():void
		{
			super.finish();
			loader.contentLoaderInfo.removeEventListener(Event.COMPLETE, completeHandler);
			loader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR, completeHandler);
			loader.contentLoaderInfo.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, completeHandler);
			loader.contentLoaderInfo.removeEventListener(HTTPStatusEvent.HTTP_STATUS, httpStatusHandler);
			loader.contentLoaderInfo.removeEventListener(ProgressEvent.PROGRESS, redispatch);
		}
		
		/**
		 * @inheritDoc
		 */
		override protected function getUrl():String
		{
			return request.url;
		}
	}
}