#!/usr/bin/env python3
"""
Minimal VM API Server

A simple HTTP API wrapper around the existing VM CLI scripts.
Follows test-first development - implements only what tests require.
"""

import json
import os
import sys
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

class MinimalVMAPIHandler(BaseHTTPRequestHandler):
    """Simple HTTP request handler for VM operations"""
    
    def do_GET(self):
        """Handle GET requests"""
        if self.path == '/health':
            self.handle_health()
        elif self.path == '/vms':
            self.handle_vms()
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
    
    def handle_vms(self):
        """Handle /vms endpoint"""
        try:
            # Get project root directory
            script_dir = os.path.dirname(os.path.abspath(__file__))
            project_root = os.path.dirname(script_dir)
            tart_bin = os.path.join(project_root, "tart-binary")
            
            # Run tart list command
            result = subprocess.run(
                [tart_bin, "list"],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            vms = []
            if result.returncode == 0 and result.stdout.strip():
                # Parse tart list output
                lines = result.stdout.strip().split('\n')
                for line in lines:
                    # Skip header line
                    if line.startswith('Source'):
                        continue
                    
                    parts = line.split()
                    if len(parts) >= 3:
                        vm_source = parts[0]
                        vm_name = parts[1] 
                        vm_status = parts[-1]  # Last column is status
                        
                        vms.append({
                            "name": vm_name,
                            "status": vm_status,
                            "source": vm_source
                        })
            
            # Send response
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            self.wfile.write(json.dumps(vms, indent=2).encode())
            
        except subprocess.TimeoutExpired:
            self.send_error(504, "Tart command timed out")
        except subprocess.CalledProcessError as e:
            self.send_error(500, f"Tart command failed: {e}")
        except Exception as e:
            self.send_error(500, f"Internal server error: {e}")
    
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