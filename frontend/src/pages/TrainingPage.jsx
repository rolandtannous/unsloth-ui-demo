import React, { useState } from 'react';
import { api } from '../services/api';

function TrainingPage() {
  const [config, setConfig] = useState({
    model_name: 'unsloth/llama-3-8b-bnb-4bit',
    dataset: 'alpaca',
    max_seq_length: 2048,
    learning_rate: 2e-4,
    num_epochs: 3,
    batch_size: 4,
    lora_r: 16,
    lora_alpha: 16,
  });

  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(false);

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setConfig((prev) => ({
      ...prev,
      [name]: value,
    }));
  };

  const handleStartTraining = async () => {
    setLoading(true);
    try {
      const response = await api.startTraining(config);
      setStatus(response);
    } catch (err) {
      setStatus({ status: 'error', message: err.message });
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="bg-white rounded-xl shadow-sm p-6">
        <h1 className="text-2xl font-bold text-gray-900">🚀 Training Configuration</h1>
        <p className="text-gray-500 mt-1">Configure and start your fine-tuning job</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Configuration Form */}
        <div className="lg:col-span-2 bg-white rounded-xl shadow-sm p-6">
          <h2 className="text-lg font-semibold text-gray-900 mb-6">Configuration</h2>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Model Selection */}
            <div className="md:col-span-2">
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Model
              </label>
              <select
                name="model_name"
                value={config.model_name}
                onChange={handleInputChange}
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-unsloth-500"
              >
                <option value="unsloth/llama-3-8b-bnb-4bit">Llama 3 8B (4-bit)</option>
                <option value="unsloth/mistral-7b-bnb-4bit">Mistral 7B (4-bit)</option>
                <option value="unsloth/gemma-7b-bnb-4bit">Gemma 7B (4-bit)</option>
              </select>
            </div>

            {/* Dataset */}
            <div className="md:col-span-2">
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Dataset
              </label>
              <select
                name="dataset"
                value={config.dataset}
                onChange={handleInputChange}
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-unsloth-500"
              >
                <option value="alpaca">Alpaca (52k samples)</option>
                <option value="dolly">Dolly (15k samples)</option>
                <option value="custom">Custom Dataset</option>
              </select>
            </div>

            {/* Max Seq Length */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Max Sequence Length
              </label>
              <input
                type="number"
                name="max_seq_length"
                value={config.max_seq_length}
                onChange={handleInputChange}
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-unsloth-500"
              />
            </div>

            {/* Learning Rate */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Learning Rate
              </label>
              <input
                type="number"
                name="learning_rate"
                value={config.learning_rate}
                onChange={handleInputChange}
                step="0.0001"
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-unsloth-500"
              />
            </div>

            {/* Epochs */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Number of Epochs
              </label>
              <input
                type="number"
                name="num_epochs"
                value={config.num_epochs}
                onChange={handleInputChange}
                min="1"
                max="100"
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-unsloth-500"
              />
            </div>

            {/* Batch Size */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Batch Size
              </label>
              <input
                type="number"
                name="batch_size"
                value={config.batch_size}
                onChange={handleInputChange}
                min="1"
                max="64"
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-unsloth-500"
              />
            </div>

            {/* LoRA R */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                LoRA Rank (r)
              </label>
              <input
                type="number"
                name="lora_r"
                value={config.lora_r}
                onChange={handleInputChange}
                min="4"
                max="128"
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-unsloth-500"
              />
            </div>

            {/* LoRA Alpha */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                LoRA Alpha
              </label>
              <input
                type="number"
                name="lora_alpha"
                value={config.lora_alpha}
                onChange={handleInputChange}
                min="4"
                max="128"
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-unsloth-500"
              />
            </div>
          </div>

          {/* Start Button */}
          <div className="mt-8">
            <button
              onClick={handleStartTraining}
              disabled={loading}
              className="w-full py-3 bg-unsloth-500 text-white rounded-lg font-semibold hover:bg-unsloth-600 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors"
            >
              {loading ? (
                <span className="flex items-center justify-center space-x-2">
                  <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                  </svg>
                  <span>Starting...</span>
                </span>
              ) : (
                '🚀 Start Training'
              )}
            </button>
          </div>
        </div>

        {/* Status Panel */}
        <div className="bg-white rounded-xl shadow-sm p-6">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Status</h2>

          {status ? (
            <div className={`p-4 rounded-lg ${
              status.status === 'error'
                ? 'bg-red-50 border border-red-200'
                : 'bg-green-50 border border-green-200'
            }`}>
              <div className="flex items-center space-x-2 mb-2">
                <span className={`w-2 h-2 rounded-full ${
                  status.status === 'error' ? 'bg-red-500' : 'bg-green-500'
                }`}></span>
                <span className={`font-medium ${
                  status.status === 'error' ? 'text-red-700' : 'text-green-700'
                }`}>
                  {status.status === 'error' ? 'Error' : 'Started'}
                </span>
              </div>
              <p className="text-sm text-gray-600">{status.message}</p>

              {status.job_id && (
                <p className="text-xs text-gray-400 mt-2">
                  Job ID: {status.job_id}
                </p>
              )}
            </div>
          ) : (
            <div className="text-center py-8 text-gray-400">
              <p className="text-4xl mb-2">🦥</p>
              <p>Ready to start training</p>
            </div>
          )}

          {/* Config Preview */}
          <div className="mt-6">
            <h3 className="text-sm font-medium text-gray-700 mb-2">
              Current Config
            </h3>
            <pre className="text-xs bg-gray-50 p-3 rounded-lg overflow-auto max-h-64">
              {JSON.stringify(config, null, 2)}
            </pre>
          </div>
        </div>
      </div>
    </div>
  );
}

export default TrainingPage;
