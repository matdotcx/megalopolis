#!/usr/bin/env python3
"""
Minimal VM API Server

A simple HTTP API wrapper around the existing VM CLI scripts.
Follows test-first development - implements only what tests require.
"""

import json
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

class MinimalVMAPIHandler(BaseHTTPRequestHandler):
    """Simple HTTP request handler for VM operations"""
    
    def do_GET(self):
        """Handle GET requests"""
        if self.path == '/health':
            self.handle_health()
        else:
            self.send_error(404, "Endpoint not found")
    
    def handle_health(self):
        """Handle /health endpoint"""
        response = {
            "status": "healthy",
            "message": "Minimal VM API is running",
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        
        self.wfile.write(json.dumps(response, indent=2).encode())
    
    def log_message(self, format, *args):
        """Custom log format"""
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {format % args}")

def main():
    """Start the minimal VM API server"""
    port = 8082
    
    print(f"Starting Minimal VM API Server on port {port}")
    print(f"Health endpoint: http://localhost:{port}/health")
    print("Press Ctrl+C to stop")
    
    server = HTTPServer(('localhost', port), MinimalVMAPIHandler)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        server.server_close()

if __name__ == "__main__":
    main()