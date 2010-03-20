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
	
	import flash.events.DataEvent;
	import flash.events.Event;
	import flash.events.HTTPStatusEvent;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.FileReference;
	import flash.net.URLRequest;
	
	[Event(name="requestComplete", type="flash.events.QueueEvent")]
	[Event(name="requestRetryDurationStarted", type="com.aaronhardy.services.events.QueueEvent")]
	[Event(name="requestRetryDurationEnded", type="com.aaronhardy.services.events.QueueEvent")]
	[Event(name="complete", type="flash.events.Event")]
	[Event(name="ioError", type="flash.events.IOErrorEvent")]
	[Event(name="securityError", type="flash.events.SecurityErrorEvent")]
	[Event(name="httpStatus", type="flash.events.HTTPStatusEvent")]
	[Event(name="progress", type="flash.events.ProgressEvent")]
	[Event(name="uploadCompleteData", type="flash.events.DataEvent")]
	/**
	 * Abstracts the processing of a FileReference upload to make it compatible with the 
	 * ServiceQueue.
	 * @see com.aaronhardy.services.IQueueableRequest
	 */
	public class UploadRequest extends NonRemotingRequestBase implements IQueueableRequest
	{
		protected var _file:FileReference;
		
		public function get file():FileReference
		{
			return _file;
		}
		
		protected var request:URLRequest;
		protected var uploadDataFieldName:String;
		protected var testUpload:Boolean;
		
		public function UploadRequest(
				file:FileReference, 
				request:URLRequest,
				uploadDataFieldName:String='Filedata',
				testUpload:Boolean=false,
				timeout:Number=0, 
				retryStatusCodes:Array=null,
				retryTimeout:Boolean=true, 
				retryIntervals:Array=null)
		{
			this._file = file;
			this.request = request;
			this.uploadDataFieldName = uploadDataFieldName;
			this.testUpload = testUpload;
			
			super(timeout, retryStatusCodes, retryTimeout, retryIntervals);
		}
		
		/**
		 * @inheritDoc
		 */
		override public function execute():void
		{
			super.execute();
			file.addEventListener(Event.COMPLETE, completeHandler);
			// See finish() for more details on the UPLOAD_COMPLETE_DATA event.
			file.addEventListener(DataEvent.UPLOAD_COMPLETE_DATA, redispatch);
			file.addEventListener(IOErrorEvent.IO_ERROR, completeHandler);
			file.addEventListener(SecurityErrorEvent.SECURITY_ERROR, completeHandler);
			file.addEventListener(HTTPStatusEvent.HTTP_STATUS, httpStatusHandler);
			file.addEventListener(ProgressEvent.PROGRESS, redispatch);
			file.upload(request);
		}
		
		/**
		 * @inheritDoc
		 */
		override protected function closeConnection():void
		{
			super.closeConnection();
			
			// Usually we would close the connection by calling the cancel() function here;
			// however, a bug has been discovered where calling file.cancel() appears
			// to have some unforeseen, undesirable effects.  Specifically, if execute()
			// is called and the server responds with an http code that forces a retry, the
			// upload would usually be canceled here and execute() would later be called again.
			// However, if the request were to fail a second time, httpStatusHandler() would never 
			// be called.  It appears as if calling file.cancel() the first time removes event 
			// listeners and, even though we're adding them again in execute(), they still act as 
			// though they were never added.  By not canceling the upload, the http status handlers 
			// continue to work across retries as you would assume they should.
			// Because the only time that it's fairly crucial to cancel a file upload is
			// when the upload is forcibly canceled by an external class, we'll only call 
			// file.cancel() from this class's cancel() function.
			
			// try
			// {
			//	file.cancel();
			// } catch (e:Error) {}
		}
		
		override public function cancel():void
		{
			super.cancel();
			
			// Usually super.cancel() calls finish() which calls closeConnection() which cancels
			// any current upload.  However, there are some issues with closeConnection() for
			// an upload request as documented in closeConnection().  We'll cancel the file upload
			// forcibly here, because it's a safe place to do so. 
			try
			{
				file.cancel();
			} catch (e:Error) {}
		}
		
		/**
		 * @inheritDoc
		 */
		override protected function finish():void
		{
			super.finish();
			// Normally we would remove event listeners here but in the case of a file upload
			// we have to deal with DataEvent.UPLOAD_COMPLETE_DATA.  This event is dispatched
			// after the Event.COMPLETE event if and only if the server returns a response.
			// When Event.COMPLETE triggers the completeHandler, the completeHandler calls
			// finish.  If we were to remove the event listener for DataEvent.UPLOAD_COMPLETE_DATA,
			// the event would never be re-dispatched.  We'll settle with not removing event
			// listeners and hope the request will be cleaned up successfully since we're using
			// weak event listeners anyway.
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