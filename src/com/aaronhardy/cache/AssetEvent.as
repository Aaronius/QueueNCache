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
	import flash.events.Event;

	/**
	 * Provides various events related to portable assets.
	 * @see com.aaronhardy.cache.PortableAsset
	 */
	public class AssetEvent extends Event
	{
		public static const INVALIDATED:String = 'invalidated';
		public static const CANCELED:String = 'canceled';
		
		private var _url:String;
		
		/**
		 * The url related to the asset for which the event is being dispatched.
		 */
		public function get url():String
		{
			return _url;
		}
		
		public function AssetEvent(type:String, url:String, bubbles:Boolean=false, cancelable:Boolean=false)
		{
			super(type, bubbles, cancelable);
			this._url = url;
		}
		
		/**
		 * @private
		 */
		override public function clone():Event
		{
			return new AssetEvent(type, url, bubbles, cancelable);
		}
	}
}