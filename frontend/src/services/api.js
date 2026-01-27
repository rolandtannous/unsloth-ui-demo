const API_BASE = process.env.REACT_APP_API_URL || "";

class ApiService {
  async request(endpoint, options = {}) {
    try {
      const response = await fetch(`${API_BASE}${endpoint}`, {
        headers: {
          "Content-Type": "application/json",
          ...options.headers,
        },
        ...options,
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      return await response.json();
    } catch (error) {
      console.error("API Error:", error);
      throw error;
    }
  }

  // Health & System
  health() {
    return this.request("/api/health");
  }

  getSystemInfo() {
    return this.request("/api/system");
  }

  // Models
  getModels() {
    return this.request("/api/models");
  }

  // Training
  startTraining(config) {
    return this.request("/api/train/start", {
      method: "POST",
      body: JSON.stringify(config),
    });
  }

  getTrainingStatus() {
    return this.request("/api/train/status");
  }

  // Echo (for testing)
  echo(text) {
    return this.request("/api/echo", {
      method: "POST",
      body: JSON.stringify({ text }),
    });
  }
}

export const api = new ApiService();
