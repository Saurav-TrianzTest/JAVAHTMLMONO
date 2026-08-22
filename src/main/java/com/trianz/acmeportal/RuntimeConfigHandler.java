package com.trianz.acmeportal;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;

import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * cz-html-1011 – Runtime Config Injection Point Handler.
 *
 * <p>Serves {@code GET /config/config.json} from the shared volume path
 * {@code ${HTML_ROOT}/config/config.json}.  In an ECS Fargate deployment the
 * SSM Agent sidecar container reads parameters from AWS SSM Parameter Store
 * and writes this file to the shared volume before the main container starts.
 * The {@code docker-entrypoint.sh} script writes a fallback file assembled
 * from environment variables when the sidecar is absent (local dev / CI).
 *
 * <p>The {@code window.__ENV__} bootstrap script embedded in
 * {@code pages/dashboard.html} (and any other HTML page that needs runtime
 * configuration) fetches this endpoint synchronously before any application
 * script executes, making all SSM-sourced values available on
 * {@code window.__ENV__} without baking environment-specific data into the
 * container image.
 *
 * <p>Response headers:
 * <ul>
 *   <li>{@code Content-Type: application/json}</li>
 *   <li>{@code Cache-Control: no-store} – prevents stale config being served
 *       from browser or CDN cache after a redeployment</li>
 * </ul>
 */
public class RuntimeConfigHandler implements HttpHandler {

    /** Path to the config file written by the SSM sidecar / entrypoint fallback. */
    private static final String HTML_ROOT = System.getenv().getOrDefault("HTML_ROOT", "/app");
    private static final Path CONFIG_FILE = Paths.get(HTML_ROOT, "config", "config.json");

    /** Minimal empty-config response returned when the file is not yet available. */
    private static final byte[] EMPTY_CONFIG =
            "{}".getBytes(StandardCharsets.UTF_8);

    @Override
    public void handle(HttpExchange exchange) throws IOException {
        // Only GET is supported; reject other methods.
        if (!"GET".equalsIgnoreCase(exchange.getRequestMethod())) {
            exchange.sendResponseHeaders(405, -1);
            return;
        }

        byte[] body;
        if (Files.exists(CONFIG_FILE)) {
            try {
                body = Files.readAllBytes(CONFIG_FILE);
            } catch (IOException e) {
                System.err.println("[RuntimeConfigHandler] Failed to read " + CONFIG_FILE + ": " + e.getMessage());
                body = EMPTY_CONFIG;
            }
        } else {
            // File not yet written – return an empty object so the client does not
            // receive a 404 that would break the synchronous XHR in the bootstrap script.
            System.err.println("[RuntimeConfigHandler] WARNING: " + CONFIG_FILE +
                    " does not exist. Returning empty config. " +
                    "Ensure the SSM sidecar or docker-entrypoint.sh has run.");
            body = EMPTY_CONFIG;
        }

        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.getResponseHeaders().set("Cache-Control", "no-store");
        exchange.sendResponseHeaders(200, body.length);
        try (OutputStream os = exchange.getResponseBody()) {
            os.write(body);
        }
    }
}
