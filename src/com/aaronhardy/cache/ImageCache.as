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
	import flash.display.BitmapData;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	
	[Event(name="invalidated", type="com.aaronhardy.AssetEvent")]
	
	/**
	 * A storage device used for image objects.  External classes that need image resources
	 * can use the ImageCache to share resources with other classes so bitmap data for a given
	 * image doesn't necessarily need to be downloaded in multiple places.  This image cache also 
	 * helps prevent flickering when scrolling up and down in lists.  It does so by keeping a
	 * reference to the most recently loaded images (first in, first out) up to a certain memory
	 * limit.  Once the limit is reached, the oldest images are de-referenced to be cleaned up
	 * (if not referenced from another location in the app).
	 * 
	 * TODO: The performance of this cache could definitely be improved by implementing a linked 
	 * list rather than an array!  
	 */
	public class ImageCache extends EventDispatcher
	{
		/**
		 * The number of bytes per bitmap data pixel.
		 */
		protected const BYTES_PER_PIXEL:uint = 4;
		
		/**
		 * All cached assets.
		 * TODO: The performance of this cache could definitely be improved by implementing a linked 
 		 * list rather than an array!
		 */
		protected var portableAssets:Array = [];
		
		/**
		 * All cached assets keyed by url.
		 */
		protected var portableAssetByUrl:Object = {};
		
		private var _storedBytes:uint = 0;
		
		[Bindable]
		/**
		 * The amount of data currently stored in the cache, in bytes.
		 */
		public function get storedBytes():uint
		{
			return _storedBytes;
		}
		
		/**
		 * @private
		 */
		protected function set storedBytes(value:uint):void
		{
			_storedBytes = value;
		}
		
		//---------------------------------------------------------------
		
		private var _maxBytes:uint = 150000000;
		
		[Bindable]
		/**
		 * The limit to how much data can be stored in the cache.
		 */
		public function get maxBytes():uint
		{
			return _maxBytes;
		}
		
		/**
		 * @private
		 */
		public function set maxBytes(value:uint):void
		{
			_maxBytes = value;
			trim();
		}
		
		//---------------------------------------------------------------
		
		/**
		 * Retrieves the cached asset for the specified url if it is already cache or creates
		 * and adds the asset to the cache if it is not already cached.
		 * 
		 * Note the PortableAsset.load() needs to be called even after the PortableAsset has been 
		 * returned. This is so external classes can load the asset using specific service queue 
		 * categories.
		 */
		public function getAsset(url:String):PortableAsset
		{
			if (portableAssetByUrl.hasOwnProperty(url))
			{
				return PortableAsset(portableAssetByUrl[url]);
			}
			else
			{
				var asset:PortableAsset = new PortableAsset(this, url);
				addAsset(asset);
				return asset;
			}
		}
		
		/**
		 * Whether the cache contains a specified asset.
		 * @param asset The asset for which to check.
		 */
		public function hasAsset(asset:PortableAsset):Boolean
		{
			return hasAssetByUrl(asset.url);
		}
		
		/**
		 * Whether the cache contains a specified asset given its url.
		 * @param url The url of the asset for which to check.
		 */
		public function hasAssetByUrl(url:String):Boolean
		{
			return portableAssetByUrl.hasOwnProperty(url);
		}
		
		/**
		 * When an asset should no longer be used or should be refreshed, this function should be
		 * called.  This will invalidate the asset and alert classes using the asset
		 * that they should pull a new asset.
		 */
		public function removeAndInvalidateAsset(url:String):void
		{
			if (portableAssetByUrl.hasOwnProperty(url))
			{
				var asset:PortableAsset = portableAssetByUrl[url];
				removeAsset(asset);
			}
			
			// Optimally we would just directly call invalidate() on the PortableAsset object, but
			// if we are no longer holding onto the asset (it's not longer cached) but something
			// else has a reference to it, we still want to be able to invalidate it.
			// The simplest way seems to be dispatching the invalidation event from here, which
			// all PortableAssets watch for (see the PortableAsset constructor) and invalidate themselves.
			dispatchEvent(new AssetEvent(AssetEvent.INVALIDATED, url));
		}
		
		/**
		 * Clears the cache.
		 */
		public function clear():void
		{
			while (portableAssets.length > 0)
			{
				removeAssetAtIndex(0);
			}
		}
		
		/**
		 * Internal class used to add an asset to appropriate arrays/dictionaries and add event
		 * listeners.
		 */
		protected function addAsset(asset:PortableAsset):void
		{
			if (!asset.url)
			{
				throw new Error("Cache asset must have url property.");
			}
			
			if (asset.data)
			{
				addAssetBytesAndTrim(asset);
			}
			else
			{
				addListeners(asset);
			}
			
			portableAssets.push(asset);
			portableAssetByUrl[asset.url] = asset;
		}
		
		/**
		 * Add's the asset bytes to the memory pool and re-evaluates the cache to see if too much 
		 * data is being stored.  If so, remove the assets which have been stored the longest until 
		 * the amount of data being stored is under the limit.
		 */
		protected function addAssetBytesAndTrim(asset:PortableAsset):void
		{
			if (asset.data is BitmapData)
			{
				var bitmapData:BitmapData = asset.data;
				storedBytes += getNumBytes(bitmapData);
				trim();
			}
			else
			{
				throw new Error('Only bitmaps are currently handled by ImageCache');
			}
		}
		
		/**
		 * Trims the oldest assets from the cache until the cache memory usage is under the
		 * specified maximum.
		 */
		protected function trim():void
		{
			while (storedBytes > maxBytes && portableAssets.length > 0)
			{
				removeAssetAtIndex(0);
			}
		}

		/**
		 * When an asset has completed loading, update the tally of bytes stored and purge the
		 * oldest assets if necessary.
		 */
		protected function assetCompleteHandler(event:Event):void
		{
			var asset:PortableAsset = PortableAsset(event.target);
			removeListeners(asset);
			addAssetBytesAndTrim(asset);
		}
		
		/**
		 * If the asset fails to load, remove the asset, event listeners, etc.
		 */
		protected function assetErrorHandler(event:Event):void
		{
			var asset:PortableAsset = PortableAsset(event.target);
			// Listeners will get removed inside removeAsset()
			removeAsset(asset);
		}
		
		/**
		 * Removes an asset from the cache arrays/dictionaries, updates the stored bytes tally, etc.
		 * @param index The index of the asset in the portableAssets array that should be removed
		 *        from the cache.
		 */
		protected function removeAssetAtIndex(index:uint):void
		{
			if (portableAssets.length > index)
			{
				var asset:PortableAsset = portableAssets[index];
				removeAsset(asset, index);
			}
			else
			{
				throw new Error('Invalid index for stored asset removal');
			}
		}
		
		/**
		 * Removes an asset from the cache.
		 * @param asset The asset to remove from the cache.
		 * @param indexHint The index of the asset in the portableAssets array if previously known.
		 *        This is only used for increased performance because the index won't have to be
		 *        retrieved again.
		 */
		protected function removeAsset(asset:PortableAsset, indexHint:int=-1):void
		{
			removeListeners(asset);
			
			if (indexHint > -1)
			{
				portableAssets.splice(indexHint, 1);
			}
			else
			{
				portableAssets.splice(portableAssets.indexOf(asset), 1);
			}
			
			delete portableAssetByUrl[asset.url];
			
			var bitmapData:BitmapData = asset.data;
			if (bitmapData)
			{
				storedBytes -= getNumBytes(bitmapData);
			}
		}
		
		protected function addListeners(asset:PortableAsset):void
		{
			asset.addEventListener(Event.COMPLETE, assetCompleteHandler);
			asset.addEventListener(IOErrorEvent.IO_ERROR, assetErrorHandler);
			asset.addEventListener(SecurityErrorEvent.SECURITY_ERROR, assetErrorHandler);
			asset.addEventListener(AssetEvent.CANCELED, assetErrorHandler);
		}
		
		/**
		 * Removed event listeners that watch for asset loading events.
		 */
		protected function removeListeners(asset:PortableAsset):void
		{
			asset.removeEventListener(Event.COMPLETE, assetCompleteHandler);
			asset.removeEventListener(IOErrorEvent.IO_ERROR, assetErrorHandler);
			asset.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, assetErrorHandler);
			asset.removeEventListener(AssetEvent.CANCELED, assetErrorHandler);
		}
		
		/**
		 * Returns the number of bytes for a given bitmapdata.
		 */
		protected function getNumBytes(bitmapData:BitmapData):uint
		{
			// This is a quick calculation but it may be over-simplifying--what about
			// screens that are 16-bit?  We can load the bitmap data into a bytearray and
			// get the byte tally but it's slow.
			return bitmapData.rect.width * bitmapData.rect.height * BYTES_PER_PIXEL;
		}
	}
}