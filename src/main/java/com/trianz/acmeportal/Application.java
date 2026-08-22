package com.trianz.acmeportal;

import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;

/**
 * Minimal backend entry point for the acme-portal-static fixture.
 * Uses only built-in JDK APIs so the module builds without external
 * dependencies or network access.
 *
 * <p>Endpoints registered:
 * <ul>
 *   <li>{@code GET /api/health}       – liveness/readiness probe (HealthHandler)</li>
 *   <li>{@code GET /config/config.json} – runtime config served from the shared
 *       volume written by the SSM Agent sidecar at ECS task startup
 *       (cz-html-1011: runtime config injection point for window.__ENV__)</li>
 * </ul>
 */
public class Application {

    public static void main(String[] args) throws Exception {
        int port = 8080;
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);

        // Health check endpoint – used by ECS/Kubernetes liveness and readiness probes.
        server.createContext("/api/health", new HealthHandler());

        // cz-html-1011: Serve the runtime config file written by the SSM Agent sidecar.
        // The docker-entrypoint.sh writes a fallback config.json when the sidecar is
        // absent (local dev / CI).  The window.__ENV__ bootstrap script in dashboard.html
        // fetches this endpoint before any application script executes.
        server.createContext("/config/config.json", new RuntimeConfigHandler());

        server.setExecutor(null);
        server.start();
        System.out.println("acme-portal-static backend listening on port " + port);
    }
}
