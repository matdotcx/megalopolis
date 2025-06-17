#!/bin/bash

echo "🏙️  Megalopolis Status Dashboard Demo"
echo "===================================="
echo ""

echo "📊 Testing API endpoint..."
./dashboard/status-api.sh | head -10
echo ""

echo "🚀 To start the dashboard, run one of:"
echo "  make dashboard                    # Foreground"
echo "  make dashboard-bg                 # Background"
echo "  python3 dashboard/server.py      # Direct"
echo ""

echo "📱 Then open: http://localhost:8090"
echo ""

echo "✨ Dashboard features:"
echo "  • Real-time status with ✅/❌/⚠️ indicators"
echo "  • Auto-refresh every 30 seconds"
echo "  • Responsive design for mobile/desktop"
echo "  • JSON API at /api/status"
echo ""

echo "🔧 Monitored components:"
echo "  • Infrastructure: Docker, Kind, kubectl, Tart"
echo "  • Kubernetes: ArgoCD, Orchard, cert-manager, ingress"
echo "  • VMs: macOS dev/CI environments"
echo "  • Support: External secrets, monitoring, Keycloak"