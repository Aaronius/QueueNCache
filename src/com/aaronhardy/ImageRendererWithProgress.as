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
	import com.aaronhardy.cache.PortableAsset;
	
	import flash.events.ProgressEvent;
	
	/**
	 * Adds a progress indicator implementation for ImageRenderer.
	 */
	public class ImageRendererWithProgress extends ImageRenderer
	{
		/**
		 * @inheritDoc
		 */
		override protected function get asset():PortableAsset
		{
			return super.asset;
		}
		
		/**
		 * @private
		 */
		override protected function set asset(value:PortableAsset):void
		{
			if (asset != value)
			{
				if (asset)
				{
					asset.removeEventListener(ProgressEvent.PROGRESS, progressHandler);
				}
				
				super.asset = value;
				
				if (asset)
				{
					asset.addEventListener(ProgressEvent.PROGRESS, progressHandler);
				}
			}
		}
		
		/**
		 * @private
		 */
		override protected function updateDisplayList(unscaledWidth:Number, unscaledHeight:Number):void
		{
			super.updateDisplayList(unscaledWidth, unscaledHeight);
			
			graphics.clear();
			
			// Only show progress if the asset hasn't already finished loading.
			if (asset && !asset.data)
			{
				var indicatorColor:uint = 0xCCCCCC;
				var percentLoaded:Number = 0
				
				if (asset.bytesTotal > 0)
				{
					percentLoaded = asset.bytesLoaded / asset.bytesTotal;
					// If the asset is actively loading, give it a different color
					indicatorColor = 0x7FFF88;
				}
				
				var indicatorPercentWidth:Number = .75;
				var indicatorPercentHeight:Number = .1; 
				
				graphics.lineStyle(1, indicatorColor);
				graphics.beginFill(indicatorColor, .5);
				graphics.drawRect(
					unscaledWidth * ((1 - indicatorPercentWidth) / 2), 
					unscaledHeight * ((1 - indicatorPercentHeight) / 2), 
					unscaledWidth * indicatorPercentWidth, 
					unscaledHeight * indicatorPercentHeight);
				graphics.endFill();
				graphics.lineStyle();
				
				graphics.beginFill(indicatorColor);
				graphics.drawRect(
					unscaledWidth * ((1 - indicatorPercentWidth) / 2), 
					unscaledHeight * ((1 - indicatorPercentHeight) / 2), 
					(unscaledWidth * indicatorPercentWidth) * percentLoaded, 
					unscaledHeight * indicatorPercentHeight);
				graphics.endFill(); 
			}
		}
		
		/**
		 * When progress is received, update the display list.
		 */
		protected function progressHandler(event:ProgressEvent):void
		{
			invalidateDisplayList();
		}
	}
}