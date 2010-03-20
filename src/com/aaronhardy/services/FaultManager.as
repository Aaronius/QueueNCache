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
	
	import flash.events.EventDispatcher;
	import flash.events.TimerEvent;
	import flash.utils.Timer;
	
	[Event(name="requestRetryDurationStarted", type="com.aaronhardy.services.events.QueueEvent")]
	[Event(name="requestRetryDurationEnded", type="com.aaronhardy.services.events.QueueEvent")]
	[Event(name="requestTimeout", type="com.aaronhardy.services.events.QueueEvent")]
	
	/**
	 * Handles timeout and status code retry attempts.
	 */
	public class FaultManager extends EventDispatcher
	{
		/**
		 * The amount of time in milliseconds to wait for a server response before
		 * triggering a timeout.
		 */
		protected var timeout:Number;
		
		/**
		 * Which HTTP status codes are eligible for a retry.
		 */
		protected var retryStatusCodes:Array;
		
		/**
		 * Whether to retry timeouts.
		 */
		protected var retryTimeout:Boolean;
		
		/**
		 * The amount of time in milliseconds to wait before retrying a request.
		 * The first interval will be used for the first retry, the second interval for the second
		 * retry, etc.
		 */
		protected var retryIntervals:Array;
		
		/**
		 * A timer used for both timing timeouts and intervals between retries.
		 */
		protected var timer:Timer = new Timer(0, 1);
		
		/**
		 * The number of retries that have been attempted thus far.
		 */
		protected var retriesAttempted:uint;
		
		/**
		 * Whether the request is waiting for a retry interval (a waiting period) to pass before
		 * a retry will occur.  If this is true, requests should ignore any results being received
		 * from the server because the request was marked invalid due to a timeout or retry-eligible
		 * HTTP status code.
		 */
		public var awaitingRetry:Boolean = false;
		
		public function FaultManager(
				timeout:Number=0, 
				retryStatusCodes:Array=null,
				retryTimeout:Boolean=true, 
				retryIntervals:Array=null)
		{
			this.timeout = timeout;
			this.retryStatusCodes = retryStatusCodes;
			this.retryTimeout = retryTimeout;
			this.retryIntervals = retryIntervals;
		}
		
		
		/**
		 * Starts the timeout timer.
		 */
		public function startTimeoutTimer():void
		{
			if (!isNaN(timeout) && timeout > 0)
			{
				cleanTimer();
				timer.addEventListener(TimerEvent.TIMER_COMPLETE, timeoutHandler);
				timer.delay = timeout;
				timer.start();
			}
		}
		
		/**
		 * Once a request receives an HTTP status code from the server, the fault manager
		 * determines if it is retry-eligible and if the max number of retries has not yet been
		 * met.  If those two conditions are met, a retry interval is started. The queue
		 * will set the request aside until the retry interval is complete and then then request
		 * will once again be added to the queue so its execute function can again be called.
		 * 
		 * @param code The HTTP status code received by the server.
		 * @return Whether a retry interval has started due to the provided HTTP status code.
		 */
		public function handleStatusCode(code:int):Boolean
		{
			if (retryStatusCodes && retryIntervals && 
					(retryStatusCodes.indexOf(code) > -1 ||
					retryStatusCodes.indexOf(String(code)) > -1 ) &&
					retryIntervals.length > 0)
			{
				return startRetryInterval();
			}
			return false;
		}
		
		/**
		 * If a timeout is triggered, attempt to start a retry interval.
		 */
		protected function timeoutHandler(event:TimerEvent):void
		{
			if (retryTimeout)
			{
				startRetryInterval();
			}
			
			dispatchEvent(new QueueEvent(QueueEvent.REQUEST_TIMEOUT));
		}
		
		/**
		 * Attempts to start a retry interval, that is, start a timer to time the waiting period 
		 * before the request's retry.  If the max number of retries has already been hit,
		 * a retry interval will not be started.
		 */
		protected function startRetryInterval():Boolean
		{
			if (retriesAttempted < retryIntervals.length)
			{
				awaitingRetry = true;
				cleanTimer();
				timer.addEventListener(
						TimerEvent.TIMER_COMPLETE, intervalTimer_intervalCompleteHandler); 
				
				var duration:Number = retryIntervals[retriesAttempted];
				if (isNaN(duration))
				{
					throw new Error('Invalid retry duration: ' + duration);
				}
				timer.delay = duration;
				timer.start();
				dispatchEvent(new QueueEvent(QueueEvent.REQUEST_RETRY_DURATION_STARTED));
			}
			else
			{
				awaitingRetry = false;
			}
			
			return awaitingRetry;
		}
		
		/**
		 * After the waiting period is over, it's time to retry the request. 
		 */
		protected function intervalTimer_intervalCompleteHandler(event:TimerEvent):void
		{
			awaitingRetry = false;
			dispatchEvent(new QueueEvent(QueueEvent.REQUEST_RETRY_DURATION_ENDED));
			retriesAttempted++;
		}
		
		/**
		 * Stops the timer whether its timing a timeout or timing a retry interval.
		 */
		public function stop():void
		{
			cleanTimer();
		}
		
		/**
		 * Removes event listeners and resets the timer.  This is important in order to let a single
		 * timer be used for multiple purposes.
		 */
		protected function cleanTimer():void
		{
			if (timer)
			{
				timer.removeEventListener(TimerEvent.TIMER_COMPLETE, timeoutHandler);
				timer.removeEventListener(TimerEvent.TIMER_COMPLETE, intervalTimer_intervalCompleteHandler); 
				timer.reset();
			}
		}
	}
}