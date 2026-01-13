#!/usr/bin/env python3
"""
Host URL Opener Service

A lightweight HTTP service that runs on macOS host to open URLs in the default browser.
Designed to bridge Docker containers to the host's browser for OAuth flows and other needs.

Security features:
- Binds only to localhost (127.0.0.1)
- Uses random authentication token
- Validates URL schemes (http, https, file)
- Prevents command injection
- Limits URL length
"""

import sys
import json
import subprocess
import uuid
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
from pathlib import Path

# Configuration
MAX_URL_LENGTH = 4096
ALLOWED_SCHEMES = {'http', 'https', 'file'}
CONFIG_DIR = None  # Will be set from command line
AUTH_TOKEN = None  # Will be generated


class URLOpenerHandler(BaseHTTPRequestHandler):
    """HTTP request handler for opening URLs"""
    
    def log_message(self, format, *args):
        """Custom logging to include timestamp"""
        sys.stderr.write(f"[{self.log_date_time_string()}] {format % args}\n")
    
    def do_POST(self):
        """Handle POST requests to open URLs"""
        if self.path != '/open':
            self.send_error(404, "Not Found")
            return
        
        # Check authentication
        auth_header = self.headers.get('Authorization', '')
        if not auth_header.startswith('Bearer '):
            self.send_error(401, "Unauthorized: Missing Bearer token")
            return
        
        token = auth_header[7:]  # Remove 'Bearer ' prefix
        if token != AUTH_TOKEN:
            self.send_error(403, "Forbidden: Invalid token")
            return
        
        # Read request body
        content_length = int(self.headers.get('Content-Length', 0))
        if content_length > MAX_URL_LENGTH:
            self.send_error(413, "Payload Too Large")
            return
        
        try:
            body = self.rfile.read(content_length).decode('utf-8')
            data = json.loads(body)
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            self.send_error(400, f"Bad Request: Invalid JSON - {e}")
            return
        
        # Validate URL
        url = data.get('url', '')
        if not url:
            self.send_error(400, "Bad Request: Missing 'url' field")
            return
        
        if len(url) > MAX_URL_LENGTH:
            self.send_error(413, "URL Too Long")
            return
        
        # Parse and validate URL scheme
        try:
            parsed = urlparse(url)
            if parsed.scheme not in ALLOWED_SCHEMES:
                self.send_error(400, f"Bad Request: Scheme '{parsed.scheme}' not allowed. Allowed: {ALLOWED_SCHEMES}")
                return
        except Exception as e:
            self.send_error(400, f"Bad Request: Invalid URL - {e}")
            return
        
        # Open URL using macOS 'open' command
        try:
            # Use subprocess with shell=False to prevent injection
            result = subprocess.run(
                ['open', url],
                capture_output=True,
                text=True,
                timeout=5,
                check=False
            )
            
            if result.returncode != 0:
                self.log_message(f"Warning: 'open' command failed with code {result.returncode}: {result.stderr}")
                self.send_error(500, f"Failed to open URL: {result.stderr}")
                return
            
            # Success
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = json.dumps({
                'success': True,
                'url': url,
                'message': 'URL opened successfully'
            })
            self.wfile.write(response.encode('utf-8'))
            self.log_message(f"Opened URL: {url}")
            
        except subprocess.TimeoutExpired:
            self.send_error(504, "Timeout opening URL")
        except Exception as e:
            self.log_message(f"Error opening URL: {e}")
            self.send_error(500, f"Internal Server Error: {e}")
    
    def do_GET(self):
        """Handle GET requests - health check only"""
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = json.dumps({'status': 'ok'})
            self.wfile.write(response.encode('utf-8'))
        else:
            self.send_error(404, "Not Found")


def write_config(port, token, config_dir):
    """Write port and token to config file for container to read"""
    config_file = Path(config_dir) / 'bridge.conf'
    try:
        with open(config_file, 'w') as f:
            f.write(f"PORT={port}\n")
            f.write(f"TOKEN={token}\n")
        os.chmod(config_file, 0o600)  # Secure permissions
        print(f"Config written to: {config_file}", file=sys.stderr)
    except Exception as e:
        print(f"Error writing config: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    global CONFIG_DIR, AUTH_TOKEN
    
    if len(sys.argv) != 2:
        print("Usage: host-url-opener.py <config_dir>", file=sys.stderr)
        print("  config_dir: Directory to write bridge.conf (shared with container)", file=sys.stderr)
        sys.exit(1)
    
    CONFIG_DIR = sys.argv[1]
    
    # Validate config directory
    config_path = Path(CONFIG_DIR)
    if not config_path.exists():
        print(f"Error: Config directory does not exist: {CONFIG_DIR}", file=sys.stderr)
        sys.exit(1)
    
    if not config_path.is_dir():
        print(f"Error: Config path is not a directory: {CONFIG_DIR}", file=sys.stderr)
        sys.exit(1)
    
    # Generate random token
    AUTH_TOKEN = str(uuid.uuid4())
    
    # Create server with random port (0 = let OS choose)
    server = HTTPServer(('127.0.0.1', 0), URLOpenerHandler)
    actual_port = server.server_port
    
    # Write config for container
    write_config(actual_port, AUTH_TOKEN, CONFIG_DIR)
    
    print(f"URL Opener Service started", file=sys.stderr)
    print(f"  Listening on: 127.0.0.1:{actual_port}", file=sys.stderr)
    print(f"  Config dir: {CONFIG_DIR}", file=sys.stderr)
    # Debug: Uncomment to log partial token
    # print(f"  Token: {AUTH_TOKEN[:8]}... (truncated)", file=sys.stderr)
    print(f"Ready to accept requests", file=sys.stderr)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...", file=sys.stderr)
        server.shutdown()
        
        # Clean up config file
        config_file = Path(CONFIG_DIR) / 'bridge.conf'
        try:
            config_file.unlink()
            print(f"Cleaned up config file: {config_file}", file=sys.stderr)
        except Exception:
            pass


if __name__ == '__main__':
    main()
