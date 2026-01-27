import React, { useState, useEffect } from 'react';
import { api } from '../services/api';
import SystemInfo from '../components/SystemInfo';
import type { HealthResponse, EchoResponse, Model } from '../types';

const HomePage: React.FC = () => {
  const [models, setModels] = useState<Model[]>([]);
  const [healthStatus, setHealthStatus] = useState<HealthResponse | null>(null);
  const [echoText, setEchoText] = useState('');
  const [echoResponse, setEchoResponse] = useState<EchoResponse | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    api.health().then(setHealthStatus).catch(console.error);
    api.getModels().then((data) => setModels(data.models)).catch(console.error);
  }, []);

  const handleEcho = async () => {
    if (!echoText.trim()) return;

    setLoading(true);
    try {
      const response = await api.echo(echoText);
      setEchoResponse(response);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      handleEcho();
    }
  };

  return (
    <div className="space-y-6">
      {/* Welcome Section */}
      <div className="bg-gradient-to-r from-unsloth-500 to-unsloth-600 rounded-xl p-8 text-white">
        <h1 className="text-3xl font-bold mb-2">Welcome to Unsloth UI 🦥</h1>
        <p className="text-unsloth-100">
          Fine-tune large language models 2x faster with 70% less memory.
        </p>

        {/* Status Badge */}
        <div className="mt-4 inline-flex items-center space-x-2 bg-white/20 rounded-full px-4 py-2">
          <div className={`w-2 h-2 rounded-full ${healthStatus ? 'bg-green-400' : 'bg-yellow-400'} animate-pulse`}></div>
          <span className="text-sm">
            {healthStatus ? 'API Connected' : 'Connecting...'}
          </span>
        </div>
      </div>

      {/* System Info */}
      <SystemInfo />

      {/* API Test Section */}
      <div className="bg-white rounded-xl shadow-sm p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">
          🧪 Test API Connection
        </h2>

        <div className="flex space-x-4">
          <input
            type="text"
            value={echoText}
            onChange={(e) => setEchoText(e.target.value)}
            placeholder="Type something to test the API..."
            className="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-unsloth-500 focus:border-transparent"
            onKeyPress={handleKeyPress}
          />
          <button
            onClick={handleEcho}
            disabled={loading || !echoText.trim()}
            className="px-6 py-2 bg-unsloth-500 text-white rounded-lg font-medium hover:bg-unsloth-600 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors"
          >
            {loading ? 'Sending...' : 'Send'}
          </button>
        </div>

        {echoResponse && (
          <div className="mt-4 p-4 bg-gray-50 rounded-lg">
            <p className="text-sm text-gray-600">Response from server:</p>
            <p className="text-gray-900 font-medium mt-1">{echoResponse.message}</p>
            <p className="text-xs text-gray-400 mt-2">
              Timestamp: {echoResponse.timestamp}
            </p>
          </div>
        )}
      </div>

      {/* Available Models */}
      <div className="bg-white rounded-xl shadow-sm p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">
          🤖 Available Models
        </h2>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {models.map((model) => (
            <div
              key={model.id}
              className="border border-gray-200 rounded-lg p-4 hover:border-unsloth-300 hover:shadow-md transition-all cursor-pointer"
            >
              <h3 className="font-semibold text-gray-900">{model.name}</h3>
              <p className="text-sm text-gray-500 mt-1">{model.description}</p>
              <div className="mt-3 flex items-center justify-between">
                <span className="text-xs bg-gray-100 text-gray-600 px-2 py-1 rounded">
                  {model.size}
                </span>
                <span className="text-xs text-unsloth-600 font-medium">
                  Select →
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default HomePage;
