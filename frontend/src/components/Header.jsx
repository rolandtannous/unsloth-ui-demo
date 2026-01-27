import React from 'react';

function Header({ currentPage, setCurrentPage }) {
  const navItems = [
    { id: 'home', label: '🏠 Home' },
    { id: 'training', label: '🚀 Training' },
  ];

  return (
    <header className="bg-white shadow-sm border-b border-gray-200">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16">
          {/* Logo */}
          <div className="flex items-center space-x-3">
            <span className="text-3xl">🦥</span>
            <div>
              <h1 className="text-xl font-bold text-gray-900">Unsloth UI</h1>
              <p className="text-xs text-gray-500">Fine-tune LLMs 2x faster</p>
            </div>
          </div>

          {/* Navigation */}
          <nav className="flex space-x-1">
            {navItems.map((item) => (
              <button
                key={item.id}
                onClick={() => setCurrentPage(item.id)}
                className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                  currentPage === item.id
                    ? 'bg-unsloth-100 text-unsloth-700'
                    : 'text-gray-600 hover:bg-gray-100'
                }`}
              >
                {item.label}
              </button>
            ))}
          </nav>
        </div>
      </div>
    </header>
  );
}

export default Header;
