package com.trianz.acmeportal;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Minimal backend entry point for the acme-portal-static fixture.
 * Uses only built-in JDK APIs so the module builds without external
 * dependencies or network access.
 *
 * Environment variables consumed at runtime:
 *   CONTACT_API_URL  – Base URL for the contact-submit API endpoint
 *                      (e.g. https://api.acme-corp.com). Injected by ECS
 *                      Fargate from AWS Secrets Manager so no environment-
 *   TIMESTAMP_RENDER_MODE – Controls timestamp rendering mode (value: "client").
 *                      specific value is baked into the container image.
 */
public class Application {

    public static void main(String[] args) throws Exception {
        int port = 8080;
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);

        // Health-check endpoint (containerization requirement)
        server.createContext("/api/health", new HealthHandler());

        // Serve contact form with server-side ENV injection
        server.createContext("/forms/contact.html", new EnvInjectingHtmlHandler("forms/contact.html"));

        // Serve dashboard page with server-side ENV injection (TIMESTAMP_RENDER_MODE for cz-html-1005)
        server.createContext("/pages/dashboard.html", new EnvInjectingHtmlHandler("pages/dashboard.html"));

        server.setExecutor(null);
        server.start();
        System.out.println("acme-portal-static backend listening on port " + port);
    }

    /**
     * Serves an HTML file from the classpath/working directory and injects
     * runtime environment variables into {@code window.__ENV__} so that
     * client-side JavaScript can resolve dynamic API endpoints without any
     * hardcoded URLs in the container image.
     */
    static class EnvInjectingHtmlHandler implements HttpHandler {

        private final String relativePath;

        EnvInjectingHtmlHandler(String relativePath) {
            this.relativePath = relativePath;
        }

        @Override
        public void handle(HttpExchange exchange) throws IOException {
            // Read the HTML template from the file system
            Path htmlFile = Paths.get(relativePath);
            String html;
            if (Files.exists(htmlFile)) {
                html = new String(Files.readAllBytes(htmlFile), StandardCharsets.UTF_8);
            } else {
                // Fallback: try classpath resource
                try (InputStream is = getClass().getClassLoader().getResourceAsStream(relativePath)) {
                    if (is == null) {
                        sendError(exchange, 404, "Not Found");
                        return;
                    }
                    html = new String(is.readAllBytes(), StandardCharsets.UTF_8);
                }
            }

            // Inject environment variables into window.__ENV__ at server-render time.
            // CONTACT_API_URL is sourced from the ECS task environment (populated via
            // AWS Secrets Manager) so the container image stays environment-agnostic.
            String contactApiUrl = System.getenv("CONTACT_API_URL");
            if (contactApiUrl == null) {
                contactApiUrl = "";
            }

            // CONTAINERIZATION FIX (cz-html-1005): Inject TIMESTAMP_RENDER_MODE from AWS Secrets
            // Manager (via ECS Fargate task definition secrets block) into window.__ENV__ so the
            // client-side script in dashboard.html can render timestamps exclusively in the browser,
            // preventing SSR hydration mismatches in Kubernetes / ECS Fargate containers.
            String timestampRenderMode = System.getenv("TIMESTAMP_RENDER_MODE");
            if (timestampRenderMode == null) {
                timestampRenderMode = "";
            }

            // CONTAINERIZATION FIX (cz-html-1011): Inject STATIC_ASSETS_BASE_URL and
            // API_BASE_URL from AWS SSM Parameter Store (via ECS Fargate task definition
            // environment/secrets blocks) into window.__ENV__ to populate the runtime
            // config injection point added to pages/dashboard.html.
            String staticAssetsBaseUrl = System.getenv("STATIC_ASSETS_BASE_URL");
            if (staticAssetsBaseUrl == null) {
                staticAssetsBaseUrl = "";
            }
            String apiBaseUrl = System.getenv("API_BASE_URL");
            if (apiBaseUrl == null) {
                apiBaseUrl = "";
            }

            String envScript = "<script>window.__ENV__ = window.__ENV__ || {}; "
                    + "window.__ENV__.CONTACT_API_URL = \""
                    + escapeJs(contactApiUrl)
                    + "\"; "
                    + "window.__ENV__.TIMESTAMP_RENDER_MODE = \""
                    + escapeJs(timestampRenderMode)
                    + "\"; "
                    + "window.__ENV__.STATIC_ASSETS_BASE_URL = \""
                    + escapeJs(staticAssetsBaseUrl)
                    + "\"; "
                    + "window.__ENV__.API_BASE_URL = \""
                    + escapeJs(apiBaseUrl)
                    + "\";</script>";

            // Replace the existing placeholder script tag or inject before </head>
            html = html.replace(
                    "<script>window.__ENV__ = window.__ENV__ || {};</script>",
                    envScript
            );
            if (!html.contains(envScript)) {
                html = html.replace("</head>", envScript + "\n</head>");
            }

            byte[] body = html.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "text/html; charset=UTF-8");
            exchange.sendResponseHeaders(200, body.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body);
            }
        }

        private static void sendError(HttpExchange exchange, int code, String message) throws IOException {
            byte[] body = message.getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(code, body.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(body);
            }
        }

        /** Minimal JS string escaping to prevent injection via env var values. */
        private static String escapeJs(String value) {
            return value
                    .replace("\\", "\\\\")
                    .replace("\"", "\\\"")
                    .replace("\n", "\\n")
                    .replace("\r", "\\r");
        }
    }
}
