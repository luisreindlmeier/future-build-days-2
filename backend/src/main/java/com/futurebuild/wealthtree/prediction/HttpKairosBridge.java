package com.futurebuild.wealthtree.prediction;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Map;

/** POSTs the intake to kairos_server.py /assessment. The AI key never touches Java. */
public class HttpKairosBridge implements KairosBridge {

    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build();
    private final ObjectMapper json;
    private final String baseUrl;
    private final Duration timeout;

    public HttpKairosBridge(ObjectMapper json, String baseUrl, Duration timeout) {
        this.json = json;
        this.baseUrl = baseUrl.replaceAll("/+$", "");
        this.timeout = timeout;
    }

    @Override
    public Map<String, Object> assessment(Map<String, Object> intake) throws Exception {
        return post("/assessment", intake);
    }

    @Override
    public Map<String, Object> projects(Map<String, Object> request) throws Exception {
        return post("/projects", request);
    }

    private Map<String, Object> post(String path, Map<String, Object> body) throws Exception {
        HttpRequest req = HttpRequest.newBuilder(URI.create(baseUrl + path))
                .timeout(timeout)
                .header("Content-Type", "application/json; charset=utf-8")
                .POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body), StandardCharsets.UTF_8))
                .build();
        HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        if (res.statusCode() != 200) throw new IllegalStateException("Kairos bridge returned HTTP " + res.statusCode());
        return json.readValue(res.body(), new TypeReference<Map<String, Object>>() {});
    }
}
