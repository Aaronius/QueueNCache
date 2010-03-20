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

package com.aaronhardy.cache
{
	import com.aaronhardy.services.LoaderRequest;
	import com.aaronhardy.services.ServiceQueue;
	
	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.display.Loader;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.URLRequest;
	
	[Event(name="complete", type="flash.events.Event")]
	[Event(name="progress", type="flash.events.ProgressEvent")]
	[Event(name="ioError", type="flash.events.IOErrorEvent")]
	[Event(name="securityError", type="flash.events.SecurityErrorEvent")]
	[Event(name="invalidated", type="com.aaronhardy.AssetEvent")]
	[Event(name="canceled", type="com.aaronhardy.AssetEvent")]
	/**
	 * Wraps an asset's data, initializes its loading process, and provides progress information.
	 * This is used so an assets data and progress can be easily shared by multiple renderers. 
	 */
	public class PortableAsset extends EventDispatcher
	{
		public function PortableAsset(cache:ImageCache, url:String)
		{
			super();
			// This is one specific way of handling asset invalidation.  In essence, every
			// portable asset watches the cache for invalidation events (regardless of whether
			// the asset is still being stored in the cache) and checks the events to see if it
			// has been invalidated.  If so, the portable asset then re-dispatches the event.
			// This is less than optimal and increases coupling between the asset and the cache
			// but it provides a simple default implementation and can be modified depending on
			// an application's framework.  Preferably an event bus would be used were all
			// renderers, assets, and caches would watch for invalidation events and act on them
			// accordingly.
			cache.addEventListener(AssetEvent.INVALIDATED, invalidateAssetHandler, false, 0, true);
			_url = url;
		}
		
		protected var _data:BitmapData;
		
		/**
		 * The asset's bitmap data.
		 */
		public function get data():BitmapData
		{
			if (invalidated)
			{
				throw new Error('This asset has been invalidated and is out-of-date.  Please ' + 
						'request an updated asset.');
			}
			
			return _data;
		}
		
		//---------------------------------------------------------------
		
		protected var _url:String;
		
		/**
		 * The asset's url.
		 */
		public function get url():String
		{
			return _url;
		}
		
		//---------------------------------------------------------------
		
		/**
		 * The number of tracked references to this asset.
		 * @see #incrementReferences()
		 * @see #decrementReferences()
		 */
		protected var references:uint;
		
		/**
		 * Increments the number of references being tracked by the asset.
		 * @see #references
		 */
		public function incrementReferences():void
		{
			references++;
		}
		
		/**
		 * Decrements the number of references being tracked by the asset.  If the new number of
		 * references equals zero and the asset hasn't been fully loaded, the loading process
		 * is canceled.  This helps ensure that the asset doesn't continue to load if nothing
		 * is referencing it and provides more expected behavior when it comes to scrolling lists
		 * with image renderers, etc.
		 * @see #references
		 */
		public function decrementReferences():void
		{
			references--;
			
			if (references == 0 && !data)
			{
				cancel();
			}
		}
		
		//---------------------------------------------------------------
		
		/**
		 * The number of bytes that have been loaded thus far for the asset.
		 */
		public var bytesLoaded:uint;
		
		/**
		 * The total number of bytes that will eventually be loaded for the asset.  This remains
		 * at zero until the HTTP response for the loading request is received.
		 */
		public var bytesTotal:uint;
		
		//---------------------------------------------------------------
		
		private var _invalidated:Boolean = false;
		
		/**
		 * Whether this asset is out-of-date.  When this is set to true, no outside objects
		 * can access the data property.
		 */
		public function get invalidated():Boolean
		{
			return _invalidated;
		}
		
		//---------------------------------------------------------------
		
		protected var _loaderRequest:LoaderRequest;
		
		/**
		 * The request wrapper for this asset used within the request queue.
		 */
		public function get loaderRequest():LoaderRequest
		{
			return _loaderRequest;
		}
		
		/**
		 * @private
		 */
		public function set loaderRequest(value:LoaderRequest):void
		{
			if (_loaderRequest)
			{
				loaderRequest.removeEventListener(Event.COMPLETE, completeHandler);
				loaderRequest.removeEventListener(ProgressEvent.PROGRESS, progressHandler);
				loaderRequest.removeEventListener(IOErrorEvent.IO_ERROR, faultHandler);
				loaderRequest.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, faultHandler);
			}
			
			_loaderRequest = value;
			
			if (_loaderRequest)
			{
				loaderRequest.addEventListener(Event.COMPLETE, completeHandler);
				loaderRequest.addEventListener(ProgressEvent.PROGRESS, progressHandler);
				loaderRequest.addEventListener(IOErrorEvent.IO_ERROR, faultHandler);
				loaderRequest.addEventListener(SecurityErrorEvent.SECURITY_ERROR, faultHandler);
			}
		}
		
		//---------------------------------------------------------------
		
		/**
		 * Initializes the loading process for the asset using the specified url, queue, and queue
		 * category.
		 */
		public function load(url:String, queue:ServiceQueue, queueCategory:String):void
		{
			_url = url;
			
			if (!queue)
			{
				throw new Error('Invalid service queue object.');
			}
			
			if (!loaderRequest && !data)
			{
				loaderRequest = new LoaderRequest(new Loader(), new URLRequest(url));
				queue.enqueue(loaderRequest, queueCategory);
			}
		}
		
		/**
		 * Cancels the loading process.
		 */
		protected function cancel():void
		{
			if (loaderRequest)
			{
				loaderRequest.cancel();
				dispatchEvent(new AssetEvent(AssetEvent.CANCELED, url));
			}
		}
		
		/**
		 * Handles and redispatches loading complete events.
		 */
		protected function completeHandler(event:Event):void
		{
			if (!(loaderRequest.loader.content is Bitmap))
			{
				throw new Error('Only bitmaps are currently supported for portable assets.');
			}
			
			_data = Bitmap(loaderRequest.loader.content).bitmapData;
			dispatchEvent(event);
			loaderRequest = null
		}
		
		/**
		 * Handles and redispatches loading progress events.
		 */
		protected function progressHandler(event:ProgressEvent):void
		{
			bytesLoaded = event.bytesLoaded;
			bytesTotal = event.bytesTotal;
			dispatchEvent(event);
		}
		
		/**
		 * Handles and redispatches loading failure events.
		 */
		protected function faultHandler(event:Event):void
		{
			dispatchEvent(event);
			loaderRequest = null;
		}
		
		/**
		 * Handles asset invalidation events.
		 */
		protected function invalidateAssetHandler(event:AssetEvent):void
		{
			if (event.url == url)
			{
				_invalidated = true;
				dispatchEvent(event);
			}
		}
	}
}