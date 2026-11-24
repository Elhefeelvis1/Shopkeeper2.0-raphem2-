import React, { useState, useEffect, useRef } from 'react';
import { Search, Package, Loader2, X } from 'lucide-react';
import { useToast } from '../context/ToastContext';
import { searchLocalProducts } from '../db/dexieDb';

const ProductSearch = ({
  categories = [],
  onAddToCart,
  modalPlacement = 'lg:left-[calc(50%)] lg:right-4'
}) => {
  const { showToast } = useToast();
  const [searchQuery, setSearchQuery] = useState({ itemName: '', category: '', minPrice: '', maxPrice: '' });
  const [searchResults, setSearchResults] = useState([]);
  const [isSearching, setIsSearching] = useState(false);
  const [isSearchResultsModalOpen, setIsSearchResultsModalOpen] = useState(false);

  const searchContainerRef = useRef(null);
  const modalRef = useRef(null);

  // Debounced dynamic product search
  useEffect(() => {
    const term = searchQuery.itemName.trim();
    if (!term && !searchQuery.category) {
      setSearchResults([]);
      setIsSearchResultsModalOpen(false);
      setIsSearching(false);
      return;
    }

    setIsSearching(true);
    const delayDebounceFn = setTimeout(async () => {
      try {
        const results = await searchLocalProducts(searchQuery);
        setSearchResults(results || []);
        setIsSearchResultsModalOpen(true);
      } catch (err) {
        console.error('Local product search error:', err);
        setSearchResults([]);
        showToast('error', 'Search failed. Please try again.');
      } finally {
        setIsSearching(false);
      }
    }, 200);

    return () => clearTimeout(delayDebounceFn);
  }, [searchQuery.itemName, searchQuery.category]);

  // Close search results when clicking outside
  useEffect(() => {
    const handleClickOutside = (event) => {
      if (
        searchContainerRef.current &&
        !searchContainerRef.current.contains(event.target) &&
        modalRef.current &&
        !modalRef.current.contains(event.target)
      ) {
        setIsSearchResultsModalOpen(false);
      }
    };

    if (isSearchResultsModalOpen) {
      document.addEventListener('mousedown', handleClickOutside);
    }
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [isSearchResultsModalOpen]);

  // Close on Escape key
  useEffect(() => {
    const handleKeyDown = (event) => {
      if (event.key === 'Escape' && isSearchResultsModalOpen) {
        setIsSearchResultsModalOpen(false);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isSearchResultsModalOpen]);

  // Immediate search on form submission (e.g. barcode scanner pressing Enter)
  const handleImmediateSearch = async (e) => {
    if (e) e.preventDefault();
    const term = searchQuery.itemName.trim();
    if (!term && !searchQuery.category) return;

    setIsSearching(true);
    try {
      const results = await searchLocalProducts(searchQuery);
      setSearchResults(results || []);
      setIsSearchResultsModalOpen(true);
    } catch (err) {
      console.error('Local product search error:', err);
      setSearchResults([]);
      showToast('error', 'Search failed. Please try again.');
    } finally {
      setIsSearching(false);
    }
  };

  const handleClose = () => {
    setIsSearchResultsModalOpen(false);
    setSearchQuery({ itemName: '', category: '', minPrice: '', maxPrice: '' });
  };

  return (
    <>
      <div
        ref={searchContainerRef}
        className="bg-white rounded-xl shadow-sm border border-gray-100 p-4 sm:p-6"
      >
        <form onSubmit={handleImmediateSearch} className="space-y-4">
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2">
            <h2 className="text-lg font-bold text-gray-800 flex items-center gap-2 shrink-0">
              <Search size={20} className="text-indigo-500" /> Product Search
            </h2>
            <select
              className="text-sm w-full sm:w-auto min-w-0 max-w-full sm:max-w-[200px] h-9 px-3 bg-gray-50/50 border border-gray-200 rounded-xl focus:ring-4 focus:ring-indigo-500/20 focus:border-indigo-500 outline-none transition-all text-gray-700 truncate"
              value={searchQuery.category}
              onChange={(e) => setSearchQuery(prev => ({ ...prev, category: e.target.value }))}
            >
              <option value="">All Categories</option>
              {categories.map((c, i) => (
                <option key={c.id || i} value={c.name}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>

          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none text-gray-400">
              <Search size={18} />
            </div>
            <input
              type="text"
              placeholder="Search product name, generic name, or scan barcode..."
              className="w-full pl-10 pr-10 h-10 bg-gray-50/50 border border-gray-200 rounded-xl focus:ring-4 focus:ring-indigo-500/20 focus:border-indigo-500 outline-none transition-all placeholder:text-gray-400 text-sm"
              value={searchQuery.itemName}
              onChange={(e) => setSearchQuery(prev => ({ ...prev, itemName: e.target.value }))}
              onFocus={() => {
                if (searchResults.length > 0 || searchQuery.itemName.trim().length > 0) {
                  setIsSearchResultsModalOpen(true);
                }
              }}
            />
            {isSearching ? (
              <div className="absolute inset-y-0 right-0 pr-3.5 flex items-center pointer-events-none text-indigo-500">
                <Loader2 size={16} className="animate-spin" />
              </div>
            ) : searchQuery.itemName ? (
              <button
                type="button"
                onClick={() => {
                  setSearchQuery(prev => ({ ...prev, itemName: '' }));
                  setSearchResults([]);
                  setIsSearchResultsModalOpen(false);
                }}
                className="absolute inset-y-0 right-0 pr-3.5 flex items-center text-gray-400 hover:text-gray-600 transition cursor-pointer"
                title="Clear search"
              >
                <X size={16} />
              </button>
            ) : null}
          </div>
        </form>
      </div>

      {isSearchResultsModalOpen && (
        <div
          ref={modalRef}
          className={`absolute top-full left-0 right-0 mt-2 z-40 lg:fixed lg:top-20 lg:bottom-4 lg:mt-0 ${modalPlacement} !m-0`}
        >
          <div className="bg-white rounded-xl shadow-2xl border border-gray-200 w-full h-full overflow-hidden flex flex-col">
            <div className="p-4 sm:p-5 border-b border-gray-100 flex justify-between items-center bg-gray-50/50">
              <h3 className="text-base sm:text-lg font-bold text-gray-800 flex items-center gap-2">
                <Search size={18} className="text-indigo-500" />
                Search Results ({searchResults.length})
              </h3>
              <button
                type="button"
                onClick={handleClose}
                className="text-gray-400 hover:text-gray-600 transition cursor-pointer text-xl font-bold p-1 leading-none"
                title="Close results"
              >
                &times;
              </button>
            </div>

            <div className="p-4 sm:p-6 flex-1 overflow-y-auto">
              {isSearching ? (
                <div className="text-center py-12 text-gray-500 flex flex-col items-center justify-center">
                  <Loader2 size={32} className="animate-spin text-indigo-500 mb-2" />
                  <p className="text-sm font-medium">Searching products...</p>
                </div>
              ) : searchResults.length > 0 ? (
                <div className="overflow-x-auto border border-gray-200 rounded-lg shadow-xs">
                  <table className="w-full text-left text-sm">
                    <thead className="bg-gray-50 text-gray-600">
                      <tr>
                        <th className="px-4 py-3 font-medium">Name</th>
                        <th className="px-4 py-3 font-medium">Category</th>
                        <th className="px-4 py-3 font-medium">Stock</th>
                        <th className="px-4 py-3 font-medium">Price</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100 bg-white">
                      {searchResults.map((item, idx) => (
                        <tr
                          key={item.item_id || item.id || idx}
                          onClick={() => {
                            const added = onAddToCart(item);
                            setIsSearchResultsModalOpen(false);
                            setSearchQuery({ itemName: '', category: '', minPrice: '', maxPrice: '' });
                            if (added === false) {
                              showToast('error', `${item.item_name} is already in the cart!`);
                            }
                          }}
                          className="hover:bg-indigo-50/80 cursor-pointer transition-colors"
                        >
                          <td className="px-4 py-3 font-semibold text-gray-800">
                            <div>{item.item_name || item.name}</div>
                            {item.generic_name && (
                              <div className="text-xs text-gray-400 font-normal">{item.generic_name}</div>
                            )}
                          </td>
                          <td className="px-4 py-3 text-gray-500">{item.category_name}</td>
                          <td className="px-4 py-3 text-gray-500">
                            <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${Number(item.total_quantity_in_stock || 0) <= 0
                                ? 'bg-red-50 text-red-600'
                                : Number(item.total_quantity_in_stock || 0) <= 5
                                  ? 'bg-amber-50 text-amber-600'
                                  : 'bg-emerald-50 text-emerald-600'
                              }`}>
                              {item.total_quantity_in_stock} {item.unit_name || 'units'}
                            </span>
                          </td>
                          <td className="px-4 py-3 font-bold text-indigo-600 whitespace-nowrap">
                            ₦{Number(item.unit_selling_price || 0).toLocaleString()}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <div className="text-center py-10 text-gray-400 bg-gray-50 rounded-lg border border-dashed border-gray-200">
                  <Package size={32} className="mx-auto mb-2 opacity-50" />
                  <p className="font-medium text-sm">No products found matching your search.</p>
                  <p className="text-xs text-gray-400 mt-1">Try another search term or category.</p>
                </div>
              )}
            </div>

            <div className="p-3 sm:p-4 border-t border-gray-100 bg-gray-50/50 flex justify-between items-center text-xs text-gray-400">
              <span>Click a product to add to cart</span>
              <button
                type="button"
                onClick={handleClose}
                className="px-4 py-1.5 bg-gray-200 hover:bg-gray-300 text-gray-700 font-medium rounded-lg transition shadow-xs cursor-pointer text-xs"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
};

export default ProductSearch;
