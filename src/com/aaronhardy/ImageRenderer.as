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

package com.aaronhardy
{
	import com.aaronhardy.cache.AssetEvent;
	import com.aaronhardy.cache.ImageCache;
	import com.aaronhardy.cache.PortableAsset;
	import com.aaronhardy.services.ServiceQueue;
	
	import flash.display.Bitmap;
	import flash.events.Event;
	
	import mx.controls.listClasses.IListItemRenderer;
	import mx.core.UIComponent;
	import mx.events.FlexEvent;
	
	/**
	 * An image renderer that works in tandem with a queue and cache system.  This currently only 
	 * handles bitmap images.
	 */
	public class ImageRenderer extends UIComponent implements IListItemRenderer
	{
		public function ImageRenderer():void
		{
			addEventListener(Event.REMOVED_FROM_STAGE, removedFromStageHandler);
		}
		
		/**
		 * The bitmap being displayed in the renderer.  The same bitmap will be used for the
		 * duration of the renderer's life but the bitmap data will be swapped.
		 */
		protected var bitmap:Bitmap;
		
		//---------------------------------------------------------------
		
		private var _data:Object;
		protected var dataChanged:Boolean = false;
		
		/**
		 * The data item for the renderer.
		 */
		public function get data():Object
		{
			return _data;
		}
		
		/**
		 * @private
		 */
		public function set data(value:Object):void
		{
			_data = value;
			dataChanged = true;
			invalidateProperties();
			invalidateDisplayList();
			dispatchEvent(new FlexEvent(FlexEvent.DATA_CHANGE));
		}
		
		//---------------------------------------------------------------
		
		private var _imageCache:ImageCache;
		
		/**
		 * The cache this renderer uses to access assets.
		 */
		public function get imageCache():ImageCache
		{
			return _imageCache;
		}
		
		/**
		 * @private
		 */
		public function set imageCache(value:ImageCache):void
		{
			_imageCache = value;
		}
		
		//---------------------------------------------------------------
		
		private var _queue:ServiceQueue;
		
		/**
		 * The queue the renderer uses for loading assets.
		 */
		public function get queue():ServiceQueue
		{
			return _queue;
		}
		
		/**
		 * @private
		 */
		public function set queue(value:ServiceQueue):void
		{
			_queue = value;
		}
		
		//---------------------------------------------------------------
		
		private var _queueCategory:String;
		
		/**
		 * The category to be used for requests coming from this renderer.  By categorizing 
		 * requests we can shift queued requests as necessary.
		 */
		public function get queueCategory():String
		{
			return _queueCategory;
		}
		
		/**
		 * @private
		 */
		public function set queueCategory(value:String):void
		{
			_queueCategory = value;
		}
		
		//---------------------------------------------------------------
		
		private var _asset:PortableAsset;
		
		/**
		 * The portable asset instance providing bitmap data and loading progress.
		 */
		protected function get asset():PortableAsset
		{
			return _asset;
		}
		
		/**
		 * @private
		 */
		protected function set asset(value:PortableAsset):void
		{
			if (_asset != value)
			{
				// Increment and decrement the reference count within PortableAsset so it can
				// take appropriate action on its request.
				if (_asset)
				{
					_asset.removeEventListener(Event.COMPLETE, asset_completeHandler);
					_asset.removeEventListener(AssetEvent.INVALIDATED, asset_invalidatedHandler);
					_asset.decrementReferences();
				}
				
				_asset = value;
				
				if (_asset)
				{
					_asset.addEventListener(Event.COMPLETE, asset_completeHandler);
					_asset.addEventListener(AssetEvent.INVALIDATED, asset_invalidatedHandler);
					_asset.incrementReferences();
				}
			}
		}
		
		//---------------------------------------------------------------
		
		/**
		 * @private
		 */
		override protected function createChildren():void
		{
			super.createChildren();
			
			bitmap = new Bitmap();
			addChild(bitmap);
		}
		
		/**
		 * @private
		 */
		override protected function commitProperties():void
		{
			super.commitProperties();
			
			if (dataChanged)
			{
				if (!data || !(data is String) || String(data).length == 0)
				{
					throw new Error('Data must be a valid url.');
				}
				
				if (!imageCache)
				{
					throw new Error('ImageCache must be set prior to loading image data.');
				}
				
				if (!queue)
				{
					throw new Error('Queue must be set prior to loading image data.');
				}
				
				asset = imageCache.getAsset(String(data));
				
				if (asset)
				{
					// Load the asset using the specified queue and queue category.
					asset.load(String(data), queue, queueCategory);
				}
				
				dataChanged = false;
			}
			
			if (asset && asset.data)
			{
				bitmap.bitmapData = asset.data;
				bitmap.smoothing = true; // This gets reset to false when setting bitmapdata above.
			}
			else
			{
				bitmap.bitmapData = null;
			}
		}
		
		/**
		 * @private
		 */
		override protected function measure():void
		{
			super.measure();
			measuredWidth = 100;
			measuredHeight = 100;
		}
		
		/**
		 * @private
		 */
		override protected function updateDisplayList(unscaledWidth:Number, unscaledHeight:Number):void
		{
			super.updateDisplayList(unscaledWidth, unscaledHeight);
			
			// Scale and center the bitmap as necessary.
			if (bitmap.bitmapData)
			{
				var scale:Number = Math.min(
						unscaledWidth / bitmap.bitmapData.width,
						unscaledHeight / bitmap.bitmapData.height);
				bitmap.width = Math.floor(bitmap.bitmapData.width * scale);
				bitmap.height = Math.floor(bitmap.bitmapData.height * scale);
				bitmap.x = unscaledWidth / 2 - bitmap.width / 2;
				bitmap.y = unscaledHeight / 2 - bitmap.height / 2;
			}
		}
		
		/**
		 * Handles when the asset reports that loading is complete.  Invalidates properties
		 * for bitmap data to be set into this renderer's bitmap.  Invalidates the display list
		 * so the bitmap can be sized and positioned appropriately.
		 */
		protected function asset_completeHandler(event:Event):void
		{
			invalidateProperties();
			invalidateDisplayList();
		}
		
		/**
		 * Handles when the asset reports it has been invalidated.  Sends the renderer through
		 * the component lifecycle with dataChanged set to true so the renderer will act like
		 * it's new data and request a new asset.
		 */
		protected function asset_invalidatedHandler(event:AssetEvent):void
		{
			dataChanged = true;
			invalidateProperties();
			invalidateDisplayList();
		}
		
		/**
		 * Handle the renderer being removed from the stage.
		 * By nulling out the asset, the reference count for the asset will be decreased and,
		 * if there are no other references, the asset will be removed from the cache and the
		 * loading process will be canceled.  While this isn't necessary, it's generally preferred.
		 * @see #asset
		 * @see com.aaronhardy.cache.PortableAsset#decrementReferences()
		 */
		protected function removedFromStageHandler(event:Event):void
		{
			asset = null;
			dataChanged = true;
			invalidateProperties();
			invalidateDisplayList();
		}
	}
}