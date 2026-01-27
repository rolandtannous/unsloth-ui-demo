import React, { useState, useEffect } from 'react';
import { api } from '../services/api';

function SystemInfo() {
  const [systemInfo, setSystemInfo] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    loadSystemInfo();
  }, []);

  const loadSystemInfo = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await api.getSystemInfo();
      setSystemInfo(data);
    } catch (err) {
      setError('Failed to load system info');
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="bg-white rounded-xl shadow-sm p-6 animate-pulse">
        <div className="h-4 bg-gray-200 rounded w-1/4 mb-4"></div>
        <div className="h-8 bg-gray-200 rounded w-1/2"></div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 rounded-xl p-6 border border-red-200">
        <p className="text-red-600">{error}</p>
        <button
          onClick={loadSystemInfo}
          className="mt-2 text-sm text-red-700 underline"
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-xl shadow-sm p-6">
      <h2 className="text-lg font-semibold text-gray-900 mb-4">
        💻 System Information
      </h2>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {/* CPU */}
        <div className="bg-gray-50 rounded-lg p-4">
          <p className="text-sm text-gray-500 mb-1">CPU Cores</p>
          <p className="text-2xl font-bold text-gray-900">
            {systemInfo?.cpu_count || 'N/A'}
          </p>
        </div>

        {/* Memory */}
        <div className="bg-gray-50 rounded-lg p-4">
          <p className="text-sm text-gray-500 mb-1">Memory</p>
          <p className="text-2xl font-bold text-gray-900">
            {systemInfo?.memory?.total_gb || 'N/A'} GB
          </p>
          <div className="mt-2 w-full bg-gray-200 rounded-full h-2">
            <div
              className="bg-unsloth-500 h-2 rounded-full"
              style={{ width: `${systemInfo?.memory?.percent_used || 0}%` }}
            ></div>
          </div>
          <p className="text-xs text-gray-500 mt-1">
            {systemInfo?.memory?.percent_used}% used
          </p>
        </div>

        {/* GPU */}
        <div className="bg-gray-50 rounded-lg p-4">
          <p className="text-sm text-gray-500 mb-1">GPU</p>
          {systemInfo?.gpu?.available ? (
            <div>
              <p className="text-lg font-bold text-gray-900">
                {systemInfo.gpu.devices[0]?.name || 'Available'}
              </p>
              <p className="text-sm text-gray-600">
                {systemInfo.gpu.devices[0]?.memory_total_gb} GB VRAM
              </p>
            </div>
          ) : (
            <p className="text-lg font-bold text-gray-400">Not Available</p>
          )}
        </div>
      </div>

      <p className="text-xs text-gray-400 mt-4">
        Platform: {systemInfo?.platform}
      </p>
    </div>
  );
}

export default SystemInfo;
