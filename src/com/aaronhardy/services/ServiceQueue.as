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
	import flash.utils.Dictionary;
	
	/**
	 * This class is used for prioritizing service calls for an application.  For example, 
	 * if you have 50 image renderers on screen and therefore 50 images loading, then you make
	 * a separate service call, you may not want to wait for all the images to be loaded before
	 * the service call is made.  The problem is, all 50 image requests have already been pushed
	 * out to the browser and have been queued.  By keeping the queue within our application,
	 * we can change the priority of queued service calls.
	 * 
	 * Any service request that should be managed within this queue must implement IQueueableRequest 
	 * and be added to the queue using the enqueue() function.
	 * 
	 * This class can be used as a singleton if desired.  The reason it does not contain a
	 * singleton in its current form is becuase (1) the developer may not want to use it as a
	 * singleton and (2) the developer will often extend this class and make the extending
	 * class a singleton, in which case there are two singletons in the inheritance chain which
	 * can be difficult to work with.
	 * 
	 * TODO: The performance of this queue could definitely be improved by implementing linked 
 	 * lists rather than arrays!
	 */
	public class ServiceQueue
	{
		/**
		 * The maximum number of requests that can be processing simultaneously.  To keep
		 * this matched up with what most browsers support, the default is 2.
		 * @default 2
		 */
		public var maxSimultaneousRequests:uint = 2;
		
		/**
		 * Requests that are currently executing.
		 * TODO: The performance of this queue could definitely be improved by implementing linked 
 	 	 * lists rather than arrays!
		 */
		protected var executing:Array = [];
		
		/**
		 * Requests that are set aside while they wait to be retried.
		 * TODO: The performance of this queue could definitely be improved by implementing linked 
 	 	 * lists rather than arrays!
		 */
		protected var awaitingRetry:Array = [];
		
		/**
		 * Requests that are waiting to be executed.
		 * TODO: The performance of this queue could definitely be improved by implementing linked 
 	 	 * lists rather than arrays!
		 */
		protected var queue:Array = [];
		
		/**
		 * A hash map where the category is the key and the value is an array of all the 
		 * requests of the category.
		 */
		protected var requestsByCategory:Object = {};
		
		/**
		 * A dictionary where the key is the request and the value is the category for the request.
		 */
		protected var categoryByRequest:Dictionary = new Dictionary();
		
		/**
		 * Store the category that's currently being forced as the top priority. This is stored
		 * so that future requests being added to the queue that match the category can be
		 * added to the top of the queue.
		 * 
		 * @default The default category is "__undefined__" and not null because null can be a 
		 * legitimate category and we don't want requests in the null category taking 
		 * top priority by default.
		 */
		protected var _topPriorityCategory:String = "__undefined__";
		
		/**
		 * Forces all requests of the specified category to take precedence over requests of other
		 * categories.  Requests of the specified category will be shifted to the top of the queue.
		 * This category will be used as a top priority for future requests as well.  In other 
		 * words, if this method is called with "myCategory" passed in and later a request
		 * is added to the queue that is of type "myCategory", the request will be added before 
		 * requests of other categories.
		 * 
		 * @param category The request category that should take priority over other categories.
		 */
		public function forceTopPriority(category:String):void
		{
			_topPriorityCategory = category;
			
			var catRequests:Array = requestsByCategory[category];
			
			if (catRequests)
			{
				for (var i:int = catRequests.length - 1; i >= 0; i--)
				{
					var request:IQueueableRequest = catRequests[i];
					var queueIndex:int = queue.indexOf(request);
					
					if (queueIndex > -1)
					{
						queue.splice(queueIndex, 1);
						queue.unshift(request);
					}
				}
			}
		}
		
		/**
		 * Adds a request to the queue.  If the request's category is the same as the top priority
		 * category most recently forced using forceTopPriority, the request will be added after all  
		 * requests of the same category but before all requests of other categories.  Otherwise,
		 * the request will be added to the end of the queue.
		 * 
		 * @param request The request to be added to the queue.
		 * @param category The category for the request being added.
		 */
		public function enqueue(request:IQueueableRequest, category:String):void
		{
			categorize(request, category);
			
			// Add the complete handler here.  The request could be canceled before it even
			// is executed, in which case we want to be sure we remove it from the queue.
			request.addEventListener(QueueEvent.REQUEST_COMPLETE, request_completeHandler);
			
			insertIntoQueue(request);
		}
		
		/**
		 * Inserts a request into the queue based off its category.
		 */
		protected function insertIntoQueue(request:IQueueableRequest):void
		{
			var requestCategory:String = categoryByRequest[request];
			if (requestCategory != _topPriorityCategory)
			{
				queue.push(request);
			}
			else
			{
				var requestIndex:uint = queue.length;
				for (var i:uint; i < queue.length; i++)
				{
					var queuedRequestCategory:String = categoryByRequest[queue[i]];
					if (queuedRequestCategory != _topPriorityCategory)
					{
						requestIndex = i;
						break;
					}
				}
				queue.splice(requestIndex, 0, request);
			}
			
			processQueue();
		}
		
		/**
		 * Evaluates the number of requests currently executing and attempts to execute
		 * requests that are currently in the queue based on the current state.
		 */
		protected function processQueue():void
		{
			var slotsAvailable:uint = maxSimultaneousRequests - executing.length;
			for (var i:uint; i < slotsAvailable; i++)
			{
				if (queue.length > 0)
				{
					var request:IQueueableRequest = IQueueableRequest(queue.shift());
					
					// If the request fails and a retry is called for, the request will dispatch
					// a retry event rather than a complete event.
					request.addEventListener(QueueEvent.REQUEST_RETRY_DURATION_STARTED, 
							request_retryDurationStartedHandler);
					
					executing.push(request);
					request.execute();
				}
			}
		}
		
		/**
		 * If a request notifies the queue that a retry duration has started, that an error
		 * or timeout occurred with the request and it needs to be set aside while it waits
		 * for a retry.  The waiting period is determined by the request and the request will
		 * let the queue know when it's time to be retried.
		 * 
		 * The request is set aside out of the executing array to give other requests a chance to
		 * execute while the failed request cools off.
		 */
		protected function request_retryDurationStartedHandler(event:QueueEvent):void
		{
			var request:IQueueableRequest = IQueueableRequest(event.target);
			request.removeEventListener(QueueEvent.REQUEST_RETRY_DURATION_STARTED, 
					request_retryDurationStartedHandler);
			
			var executingIndex:int = executing.indexOf(request);
			if (executingIndex > -1)
			{
				executing.splice(executingIndex, 1);
				awaitingRetry.push(request);
				request.addEventListener(QueueEvent.REQUEST_RETRY_DURATION_ENDED,
						request_retryDurationEndedHandler);
			}
			
			processQueue();
		}
		
		/**
		 * The request has waiting the required amount of time after an error or timeout occured
		 * and its now ready to be executed again.  It will be placed back into the queue, but
		 * the request may or may not be added to the top of the queue.  It will be indexed as 
		 * though it were a new request. This is probably the most desirable scenario since, if the 
		 * request failed once already, we might as well wait until other potentially successful 
		 * requests are fulfilled before retrying this failed request again.
		 */
		protected function request_retryDurationEndedHandler(event:QueueEvent):void
		{
			var request:IQueueableRequest = IQueueableRequest(event.target);
			request.removeEventListener(QueueEvent.REQUEST_RETRY_DURATION_ENDED,
					request_retryDurationEndedHandler);
			
			var awaitingRetryIndex:int = awaitingRetry.indexOf(request);
			if (awaitingRetryIndex > -1)
			{
				awaitingRetry.splice(awaitingRetryIndex, 1);
				
				// By using the insertIntoQueue function, the request may or may not be added
				// to the top of the queue.  It will be indexed as though it were a new request.
				// This is probably the most desirable scenario since if the request failed once 
				// already, we might as well wait until other potentially successful requests are 
				// fulfilled before retrying this failed request again.
				insertIntoQueue(request);
			}
			
			processQueue();
		}
		
		/**
		 * Removes requests after they've completed execution and attempts to proceed to other 
		 * requests in the queue.
		 */
		protected function request_completeHandler(event:Event):void
		{
			var request:IQueueableRequest = IQueueableRequest(event.target);
			cleanupRequestForRemoval(request);
			
			if (executing.indexOf(request) > -1)
			{
				executing.splice(executing.indexOf(request), 1);
				processQueue();
			}
			else if (awaitingRetry.indexOf(request) > -1)
			{
				awaitingRetry.splice(executing.indexOf(request), 1);
			}
			else if (queue.indexOf(request) > -1)
			{
				queue.splice(queue.indexOf(request), 1);
			}
		}
		
		/**
		 * Removes all requests of the specified category from the queue.
		 * 
		 * @param category All requests for the specified category will be removed from the queue.
		 */
		public function removeCategoryFromQueue(category:String):void
		{
			if (requestsByCategory[category] != undefined)
			{
				var catRequests:Array = requestsByCategory[category];
				
				// Create a copy because within our loop we will be removing the requests
				// from our original array.  We don't want the index to get thrown off.
				catRequests = catRequests.slice();
				
				for each (var request:IQueueableRequest in catRequests)
				{
					dequeue(request);
				}
			}
		}
		
		/**
		 * Removes the specified request from the queue.
		 * 
		 * @param request The request that will be removed from the queue.
		 */
		public function dequeue(request:IQueueableRequest):void
		{
			var requestIndex:int = queue.indexOf(request);
			
			// Only remove the request from the queue if it's in the queue.
			// Notice that we're currently not removing the request if it's currently executing
			// or awaiting a retry.  We may want to change this later.
			if (requestIndex > -1)
			{
				cleanupRequestForRemoval(request);
				queue.splice(requestIndex, 1);
			}
		}
		
		/**
		 * Maps the request-category combo for easy access.
		 * 
		 * @request The request to categorize.
		 */
		protected function categorize(request:IQueueableRequest, category:String):void
		{
			// Add entry for requestsByCategory
			if (requestsByCategory[category] == undefined)
			{
				requestsByCategory[category] = [];
			}
			(requestsByCategory[category] as Array).push(request);
			
			// Add entry for categoryByRequest
			categoryByRequest[request] = category;
		}
		
		/**
		 * Removes the request-category combo from maps.
		 * 
		 * @request The request to uncategorize.
		 */
		protected function uncategorize(request:IQueueableRequest):void
		{
			var requestCategory:String = categoryByRequest[request];
						
			// Remove entry for requestsByCategory
			var categoryRequests:Array = requestsByCategory[requestCategory] as Array;
			
			if (categoryRequests)
			{
				var requestIndex:int = categoryRequests.indexOf(request);
				
				if (requestIndex > -1)
				{
					categoryRequests.splice(categoryRequests.indexOf(request), 1);
				}
				if (categoryRequests.length == 0)
				{
					delete requestsByCategory[requestCategory];
				}
			}
			
			// Remove entry for categoryByRequest
			delete categoryByRequest[request];
		}
		
		/**
		 * Removes event listeners and uncategorizes a request.  It does NOT remove the request
		 * from the executing, awaitingRetry, or queue arrays.
		 */
		protected function cleanupRequestForRemoval(request:IQueueableRequest):void
		{
			request.removeEventListener(Event.COMPLETE, request_completeHandler);
			request.removeEventListener(QueueEvent.REQUEST_RETRY_DURATION_STARTED, 
					request_retryDurationStartedHandler);
			request.removeEventListener(QueueEvent.REQUEST_RETRY_DURATION_ENDED,
					request_retryDurationEndedHandler);
			uncategorize(request);
		}
	}
}