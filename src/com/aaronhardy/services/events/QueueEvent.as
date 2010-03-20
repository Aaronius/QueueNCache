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

package com.aaronhardy.services.events
{
	import flash.events.Event;

	/**
	 * Used for any service queue-related events.
	 */
	public class QueueEvent extends Event
	{
		/**
		 * Dispatched by the FaultManager and re-dispatched by requests.  Used to notify the queue
		 * that the request should be set aside while awaiting a retry.
		 */
		public static const REQUEST_RETRY_DURATION_STARTED:String = 'requestRetryDurationStarted';
		
		/**
		 * Dispatched by the FaultManager and re-dispatched by requests.  Used to notify the queue
		 * that the request has finished waiting for a retry and should now be placed back in the
		 * queue for re-execution.
		 */
		public static const REQUEST_RETRY_DURATION_ENDED:String = 'requestRetryDurationEnded';
		
		/**
		 * Dispatched by requests when they are complete and should be removed completely from
		 * the queue.  This is dispatched regardless of the request's success.
		 */
		public static const REQUEST_COMPLETE:String = 'requestComplete';
		
		/**
		 * Dispatched by the FaultManager when a timeout has occured.
		 */
		public static const REQUEST_TIMEOUT:String = 'requestTimeout';
		
		public function QueueEvent(type:String, bubbles:Boolean=false, cancelable:Boolean=false)
		{
			super(type, bubbles, cancelable);
		}
		
		override public function clone():Event
		{
			return new QueueEvent(type, bubbles, cancelable);
		}
		
	}
}