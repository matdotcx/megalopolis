#!/usr/bin/env python3

import http.server
import socketserver
import json
import subprocess
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

class MegalopolisStatusHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        # Set the directory to serve files from
        self.dashboard_dir = Path(__file__).parent
        super().__init__(*args, directory=str(self.dashboard_dir), **kwargs)
    
    def do_GET(self):
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/api/status':
            self.handle_status_api()
        elif parsed_path.path == '/' or parsed_path.path == '/index.html':
            self.handle_dashboard()
        else:
            # Serve static files
            super().do_GET()
    
    def handle_status_api(self):
        """Handle API request for status data"""
        try:
            # Run the status script from project root directory
            script_path = self.dashboard_dir / 'status-api.sh'
            project_root = self.dashboard_dir.parent
            result = subprocess.run([str(script_path)], 
                                  capture_output=True, 
                                  text=True, 
                                  timeout=30,
                                  cwd=str(project_root))
            
            if result.returncode == 0:
                # Parse and validate JSON
                try:
                    status_data = json.loads(result.stdout)
                    self.send_json_response(status_data)
                except json.JSONDecodeError as e:
                    self.send_error_response(f"Invalid JSON from status script: {e}")
            else:
                error_msg = f"Status script failed (code {result.returncode}): stdout={result.stdout}, stderr={result.stderr}"
                print(f"DEBUG: {error_msg}")  # Add debug logging
                self.send_error_response(error_msg)
                
        except subprocess.TimeoutExpired:
            self.send_error_response("Status check timed out")
        except Exception as e:
            self.send_error_response(f"Unexpected error: {e}")
    
    def handle_dashboard(self):
        """Serve the main dashboard HTML"""
        try:
            index_path = self.dashboard_dir / 'index.html'
            with open(index_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Expires', '0')
            self.end_headers()
            self.wfile.write(content.encode('utf-8'))
        except Exception as e:
            self.send_error_response(f"Failed to serve dashboard: {e}")
    
    def send_json_response(self, data):
        """Send JSON response with proper headers"""
        json_data = json.dumps(data, indent=2)
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        self.end_headers()
        self.wfile.write(json_data.encode('utf-8'))
    
    def send_error_response(self, message):
        """Send error response as JSON"""
        error_data = {
            "error": message,
            "timestamp": subprocess.check_output(['date', '-u', '+%Y-%m-%dT%H:%M:%SZ']).decode().strip()
        }
        
        self.send_response(500)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(error_data).encode('utf-8'))
    
    def log_message(self, format, *args):
        """Custom log format"""
        sys.stderr.write(f"[{self.date_time_string()}] {format % args}\n")

def main():
    # Default port
    port = 8090
    
    # Check if port argument provided
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print(f"Invalid port number: {sys.argv[1]}")
            sys.exit(1)
    
    # Verify status script exists
    script_path = Path(__file__).parent / 'status-api.sh'
    if not script_path.exists():
        print(f"Error: Status script not found at {script_path}")
        sys.exit(1)
    
    # Make sure script is executable
    os.chmod(script_path, 0o755)
    
    try:
        with socketserver.TCPServer(("", port), MegalopolisStatusHandler) as httpd:
            print(f"🏙️  Megalopolis Status Dashboard")
            print(f"📊 Server running on http://localhost:{port}")
            print(f"🔄 API endpoint: http://localhost:{port}/api/status")
            print(f"⏹️  Press Ctrl+C to stop")
            print()
            
            try:
                httpd.serve_forever()
            except KeyboardInterrupt:
                print("\n🛑 Server stopped by user")
    
    except OSError as e:
        if e.errno == 48:  # Address already in use
            print(f"❌ Error: Port {port} is already in use")
            print(f"💡 Try a different port: python3 dashboard/server.py {port + 1}")
        else:
            print(f"❌ Error starting server: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()