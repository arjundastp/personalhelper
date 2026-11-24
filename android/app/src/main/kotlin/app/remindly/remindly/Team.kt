package app.remindly.remindly

import android.app.Activity
import android.content.Context
import android.text.Html
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.summarization.Summarization
import com.google.mlkit.genai.summarization.SummarizationRequest
import com.google.mlkit.genai.summarization.SummarizerOptions
import com.microsoft.identity.client.AcquireTokenSilentParameters
import com.microsoft.identity.client.AuthenticationCallback
import com.microsoft.identity.client.IAuthenticationResult
import com.microsoft.identity.client.ISingleAccountPublicClientApplication
import com.microsoft.identity.client.PublicClientApplication
import com.microsoft.identity.client.SignInParameters
import com.microsoft.identity.client.exception.MsalException
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Team summary: reads yesterday's Microsoft Teams chats, read-only, and summarises them on the phone.
 * Two connection types: Microsoft Graph with Chat.Read (default; Microsoft enforces read-only), or the
 * company's Microsoft 365 Teams MCP server (Agent 365), where only read tools may be called.
 *
 * Privacy rules enforced here:
 *  - The tenant ID and client ID are typed in by the user and stored on the phone only.
 *  - Only tools whose names are clearly read operations can be called (see [isReadOnlyTool]).
 *  - Raw messages live only in memory during a run; only the summary is returned and stored.
 *  - The only network hosts are Microsoft sign-in and the Agent 365 MCP endpoint.
 */
object Team {
    /**
     * Default permission: the shared Agent 365 Tools resource with the Teams scope. Tenants on the
     * newer per-server model use the Teams server's own app ID with Tools.ListInvoke.All instead;
     * the user can paste that (and a different server address) under Advanced in setup.
     */
    const val DEFAULT_SCOPE = "ea9ffc3e-8a23-4a7d-836d-234d7c7565c1/McpServers.Teams.All"
    const val DEFAULT_SERVER = "https://agent365.svc.cloud.microsoft/agents/tenants/{tenantId}/servers/mcp_TeamsServer"
    /** Redirect registered in Entra for the DayMate release key. */
    private const val REDIRECT = "msauth://app.remindly.remindly/ymbEzhxy1RuqwwTJiVcOaBSdvIA%3D"
    private const val MAX_CHATS = 30

    private val writeWords = listOf(
        "post", "send", "create", "update", "delete", "remove", "reply", "add", "set", "patch",
        "edit", "archive", "unarchive", "pin", "unpin", "invite", "mark", "hide", "unhide", "install",
        "uninstall", "upload", "move", "copy", "forward", "react", "share", "write", "put",
    )

    /** True only for tools that are plainly read operations (list / get / search / read). */
    fun isReadOnlyTool(name: String): Boolean {
        val n = name.lowercase()
        if (writeWords.any { n.contains(it) }) return false
        val core = n.substringAfterLast('_').ifEmpty { n }
        return listOf("list", "get", "search", "read").any { core.startsWith(it) || n.startsWith(it) || n.contains("_$it") }
    }

    // ---------------- sign-in (MSAL) ----------------

    private var app: ISingleAccountPublicClientApplication? = null
    private var appKey: String? = null

    /** "graph" (default): Microsoft Graph with Chat.Read. "mcp": the company's Teams MCP server. */
    private fun graphMode(ctx: Context) = Store.team(ctx).optString("mode", "graph") != "mcp"

    private fun scopes(ctx: Context): List<String> =
        if (graphMode(ctx)) listOf("https://graph.microsoft.com/Chat.Read", "https://graph.microsoft.com/User.Read")
        else listOf(Store.team(ctx).optString("scope").trim().ifEmpty { DEFAULT_SCOPE })

    private fun server(ctx: Context, tenant: String): String =
        Store.team(ctx).optString("serverUrl").trim().ifEmpty { DEFAULT_SERVER }.replace("{tenantId}", tenant)

    private fun ids(ctx: Context): Pair<String, String> {
        val t = Store.team(ctx)
        val tenant = t.optString("tenantId").trim()
        val client = t.optString("clientId").trim()
        require(tenant.isNotEmpty() && client.isNotEmpty()) { "Enter the tenant ID and client ID first." }
        return tenant to client
    }

    /** Creates (or reuses) the MSAL client from the IDs saved on the phone. Call off the main thread. */
    @Synchronized
    private fun client(ctx: Context): ISingleAccountPublicClientApplication {
        val (tenant, clientId) = ids(ctx)
        val key = "$tenant|$clientId"
        app?.let { if (appKey == key) return it }
        val cfg = JSONObject().apply {
            put("client_id", clientId)
            put("authorization_user_agent", "DEFAULT")
            put("redirect_uri", REDIRECT)
            put("account_mode", "SINGLE")
            put("broker_redirect_uri_registered", true)
            put("authorities", JSONArray().put(JSONObject().apply {
                put("type", "AAD")
                put("default", true)
                put("audience", JSONObject().put("type", "AzureADMyOrg").put("tenant_id", tenant))
            }))
        }
        val file = File(ctx.filesDir, "msal_config.json").apply { writeText(cfg.toString()) }
        val created = PublicClientApplication.createSingleAccountPublicClientApplication(ctx.applicationContext, file)
        app = created
        appKey = key
        return created
    }

    fun signIn(activity: Activity, done: (Result<String>) -> Unit) {
        Thread {
            try {
                val c = client(activity)
                runCatching { c.signOut() } // start clean if a different account was used before
                activity.runOnUiThread {
                    c.signIn(
                        SignInParameters.builder()
                            .withActivity(activity)
                            .withScopes(scopes(activity))
                            .withCallback(object : AuthenticationCallback {
                                override fun onSuccess(r: IAuthenticationResult) = done(Result.success(r.account.username))
                                override fun onError(e: MsalException) = done(Result.failure(e))
                                override fun onCancel() = done(Result.failure(IllegalStateException("Sign-in cancelled")))
                            })
                            .build()
                    )
                }
            } catch (e: Exception) {
                activity.runOnUiThread { done(Result.failure(e)) }
            }
        }.start()
    }

    fun signOut(ctx: Context) {
        runCatching { client(ctx).signOut() }
        app = null
        appKey = null
        File(ctx.filesDir, "msal_config.json").delete()
    }

    private fun token(ctx: Context): Pair<String, String> {
        val c = client(ctx)
        val account = c.currentAccount?.currentAccount ?: error("Not signed in. Tap Sign in first.")
        val (tenant, _) = ids(ctx)
        val r = c.acquireTokenSilent(
            AcquireTokenSilentParameters.Builder()
                .forAccount(account)
                .fromAuthority("https://login.microsoftonline.com/$tenant")
                .withScopes(scopes(ctx))
                .build()
        )
        return r.accessToken to account.username
    }

    // ---------------- MCP client (Streamable HTTP, JSON-RPC) ----------------

    private class Mcp(private val url: String, private val token: String) {
        private var session: String? = null
        private var nextId = 1

        private fun post(body: JSONObject): Pair<Int, String?> {
            val c = URL(url).openConnection() as HttpURLConnection
            try {
                c.requestMethod = "POST"
                c.connectTimeout = 20_000
                c.readTimeout = 60_000
                c.doOutput = true
                c.setRequestProperty("Content-Type", "application/json")
                c.setRequestProperty("Accept", "application/json, text/event-stream")
                c.setRequestProperty("Authorization", "Bearer $token")
                session?.let { c.setRequestProperty("Mcp-Session-Id", it) }
                if (session != null) c.setRequestProperty("MCP-Protocol-Version", "2025-06-18")
                c.outputStream.use { it.write(body.toString().toByteArray()) }
                val code = c.responseCode
                c.getHeaderField("Mcp-Session-Id")?.let { session = it }
                val stream = if (code in 200..299) c.inputStream else c.errorStream
                val text = stream?.bufferedReader()?.use { it.readText() }
                if (code !in 200..299) {
                    error("Teams server answered $code${if (code == 401 || code == 403) " (permission not granted yet?)" else ""}: ${text?.take(300) ?: ""}")
                }
                val type = c.contentType ?: ""
                return code to (if (type.contains("event-stream")) sseResult(text ?: "") else text)
            } finally {
                c.disconnect()
            }
        }

        /** Picks the JSON-RPC response out of an SSE body. */
        private fun sseResult(text: String): String? = text.lineSequence()
            .filter { it.startsWith("data:") }
            .map { it.removePrefix("data:").trim() }
            .lastOrNull { runCatching { JSONObject(it).has("id") }.getOrDefault(false) }

        fun rpc(method: String, params: JSONObject = JSONObject()): JSONObject {
            val id = nextId++
            val (_, text) = post(JSONObject().put("jsonrpc", "2.0").put("id", id).put("method", method).put("params", params))
            val obj = JSONObject(text ?: error("Empty answer from Teams server"))
            obj.optJSONObject("error")?.let { error("Teams server error: ${it.optString("message")}") }
            return obj.optJSONObject("result") ?: JSONObject()
        }

        fun notify(method: String) {
            runCatching { post(JSONObject().put("jsonrpc", "2.0").put("method", method)) }
        }

        fun start() {
            rpc("initialize", JSONObject()
                .put("protocolVersion", "2025-06-18")
                .put("capabilities", JSONObject())
                .put("clientInfo", JSONObject().put("name", "DayMate").put("version", "1.8")))
            notify("notifications/initialized")
        }

        fun tools(): List<JSONObject> {
            val out = ArrayList<JSONObject>()
            var cursor: String? = null
            do {
                val r = rpc("tools/list", JSONObject().apply { cursor?.let { put("cursor", it) } })
                val arr = r.optJSONArray("tools") ?: JSONArray()
                for (i in 0 until arr.length()) out.add(arr.getJSONObject(i))
                cursor = r.optStringOrNull("nextCursor")
            } while (cursor != null)
            return out
        }

        /** The ONLY way tools are called. Anything that isn't a read tool is refused here. */
        fun call(name: String, args: JSONObject): JSONObject {
            if (!isReadOnlyTool(name)) throw SecurityException("Blocked non-read tool: $name")
            return rpc("tools/call", JSONObject().put("name", name).put("arguments", args))
        }
    }

    // ---------------- parsing helpers ----------------

    /** Tool results come back as text content holding JSON; find the first array of objects inside. */
    private fun items(result: JSONObject): List<JSONObject> {
        val texts = ArrayList<String>()
        result.optJSONArray("content")?.let { c -> for (i in 0 until c.length()) c.optJSONObject(i)?.optString("text")?.let(texts::add) }
        result.optJSONObject("structuredContent")?.let { texts.add(it.toString()) }
        for (t in texts) {
            val parsed: Any = runCatching { JSONObject(t) }.getOrNull() ?: runCatching { JSONArray(t) }.getOrNull() ?: continue
            findArray(parsed)?.let { arr -> return (0 until arr.length()).mapNotNull { arr.optJSONObject(it) } }
        }
        return emptyList()
    }

    private fun findArray(v: Any, depth: Int = 0): JSONArray? {
        if (depth > 4) return null
        return when (v) {
            is JSONArray -> if (v.length() == 0 || v.opt(0) is JSONObject) v else null
            is JSONObject -> {
                for (k in listOf("value", "chats", "messages", "items", "results", "data")) {
                    v.opt(k)?.let { inner -> findArray(inner, depth + 1)?.let { return it } }
                }
                v.keys().asSequence().mapNotNull { k -> (v.opt(k) as? JSONArray)?.let { findArray(it, depth + 1) } }.firstOrNull()
            }
            else -> null
        }
    }

    private fun plain(html: String): String =
        Html.fromHtml(html, Html.FROM_HTML_MODE_COMPACT).toString().replace(Regex("\\s+"), " ").trim()

    private fun idParam(tool: JSONObject, contains: String): String {
        val props = tool.optJSONObject("inputSchema")?.optJSONObject("properties") ?: return "chatId"
        val keys = props.keys().asSequence().toList()
        return keys.firstOrNull { it.lowercase().contains(contains) && it.lowercase().contains("id") }
            ?: keys.firstOrNull { it.lowercase() == "id" } ?: "chatId"
    }

    private fun limitArgs(tool: JSONObject, args: JSONObject): JSONObject {
        val props = tool.optJSONObject("inputSchema")?.optJSONObject("properties") ?: return args
        props.keys().asSequence().firstOrNull { it.lowercase().trimStart('$') in setOf("top", "limit", "pagesize", "maxresults") }
            ?.let { args.put(it, 50) }
        return args
    }

    // ---------------- the daily pull ----------------

    // ---------------- Microsoft Graph (read-only: Chat.Read, GET requests only) ----------------

    private const val GRAPH = "https://graph.microsoft.com/v1.0"

    /** The ONLY way Graph is called: GET to graph.microsoft.com. Chat.Read itself cannot write. */
    private fun graphGet(token: String, url: String): JSONObject {
        require(url.startsWith("$GRAPH/")) { "Blocked request outside Microsoft Graph" }
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.requestMethod = "GET"
            c.connectTimeout = 20_000
            c.readTimeout = 60_000
            c.setRequestProperty("Authorization", "Bearer $token")
            c.setRequestProperty("Accept", "application/json")
            val code = c.responseCode
            val text = (if (code in 200..299) c.inputStream else c.errorStream)?.bufferedReader()?.use { it.readText() } ?: ""
            if (code !in 200..299) {
                val msg = runCatching { JSONObject(text).optJSONObject("error")?.optString("message") }.getOrNull() ?: text.take(200)
                error("Microsoft Graph answered $code${if (code == 401 || code == 403) " (Chat.Read not approved yet?)" else ""}: $msg")
            }
            return JSONObject(text)
        } finally {
            c.disconnect()
        }
    }

    private fun values(o: JSONObject): List<JSONObject> =
        o.optJSONArray("value")?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it) } } ?: emptyList()

    private fun enc(s: String) = java.net.URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    // ---------------- the daily pull ----------------

    /**
     * Reads yesterday's chat messages (read-only), summarises them on the phone and returns
     * a JSON summary plus a diagnostics block (no message text in diagnostics).
     */
    fun pullYesterday(ctx: Context): JSONObject {
        val started = System.currentTimeMillis()
        val diag = JSONObject()
        val (tenant, _) = ids(ctx)
        val (accessToken, username) = token(ctx)
        val zone = ZoneId.systemDefault()
        val day = LocalDate.now(zone).minusDays(1)
        val from = day.atStartOfDay(zone).toInstant()
        val to = day.plusDays(1).atStartOfDay(zone).toInstant()

        val chats: List<JSONObject>
        val fetch: (JSONObject) -> List<JSONObject>
        var myName = username.substringBefore('@').substringBefore('.')

        if (graphMode(ctx)) {
            diag.put("mode", "Microsoft Graph (Chat.Read)")
            runCatching { graphGet(accessToken, "$GRAPH/me?\$select=displayName").optStringOrNull("displayName") }.getOrNull()?.let { myName = it }
            val listUrl = "$GRAPH/me/chats?\$top=50&\$expand=lastMessagePreview&\$orderby=${enc("lastMessagePreview/createdDateTime desc")}"
            chats = runCatching { values(graphGet(accessToken, listUrl)) }
                .getOrElse { values(graphGet(accessToken, "$GRAPH/me/chats?\$top=50&\$expand=lastMessagePreview")) }
            fetch = { chat ->
                val out = ArrayList<JSONObject>()
                var url: String? = "$GRAPH/me/chats/${enc(chat.optString("id"))}/messages?\$top=50&\$orderby=${enc("createdDateTime desc")}"
                var pages = 0
                while (url != null && pages++ < 4) {
                    val page = graphGet(accessToken, url)
                    val items = values(page)
                    out.addAll(items)
                    val oldest = items.lastOrNull()?.optStringOrNull("createdDateTime")?.let { runCatching { Instant.parse(it) }.getOrNull() }
                    url = if (oldest != null && oldest.isAfter(from)) page.optStringOrNull("@odata.nextLink") else null
                }
                out
            }
        } else {
            diag.put("mode", "Teams MCP server")
            val mcp = Mcp(server(ctx, tenant), accessToken)
            mcp.start()
            val all = mcp.tools()
            val readTools = all.filter { isReadOnlyTool(it.optString("name")) }
            diag.put("toolsTotal", all.size)
            diag.put("toolsAllowed", JSONArray(readTools.map { it.optString("name") }))
            diag.put("toolsBlocked", all.size - readTools.size)
            fun find(vararg must: String, not: String? = null) = readTools.firstOrNull { t ->
                val n = t.optString("name").lowercase()
                must.all { n.contains(it) } && (not == null || !n.contains(not))
            }
            val listChats = find("list", "chat", not = "message") ?: error("No read tool for listing chats was found on the Teams server.")
            val listMessages = find("list", "chat", "message") ?: find("list", "message") ?: error("No read tool for chat messages was found.")
            diag.put("chatTool", listChats.optString("name"))
            diag.put("messageTool", listMessages.optString("name"))
            chats = items(mcp.call(listChats.optString("name"), limitArgs(listChats, JSONObject())))
            val idKey = idParam(listMessages, "chat")
            fetch = { chat -> items(mcp.call(listMessages.optString("name"), limitArgs(listMessages, JSONObject().put(idKey, chat.optString("id"))))) }
        }
        diag.put("chatsListed", chats.size)

        // Skip chats with no activity since yesterday started (when the server tells us).
        val recent = chats.filter { c ->
            val t = c.optJSONObject("lastMessagePreview")?.optStringOrNull("createdDateTime") ?: c.optStringOrNull("lastUpdatedDateTime")
            t == null || runCatching { !Instant.parse(t).isBefore(from) }.getOrDefault(true)
        }.take(MAX_CHATS)

        val firstName = myName.substringBefore(' ').lowercase()
        val perChat = JSONArray()
        val actions = JSONArray()
        var totalMessages = 0
        val chatTexts = ArrayList<Pair<String, String>>()

        for (c in recent) {
            if (c.optString("id").isEmpty()) continue
            val msgs = runCatching { fetch(c) }.getOrElse { emptyList() }
            val senders = LinkedHashSet<String>()
            val lines = msgs.mapNotNull { m ->
                val created = m.optStringOrNull("createdDateTime") ?: return@mapNotNull null
                val at = runCatching { Instant.parse(created) }.getOrNull() ?: return@mapNotNull null
                if (at.isBefore(from) || !at.isBefore(to)) return@mapNotNull null
                if (m.optString("messageType", "message") != "message") return@mapNotNull null
                val text = plain(m.optJSONObject("body")?.optString("content") ?: "")
                if (text.isBlank()) return@mapNotNull null
                val who = m.optJSONObject("from")?.optJSONObject("user")?.optString("displayName")?.ifBlank { null } ?: "Someone"
                senders.add(who)
                at to "$who: $text"
            }.sortedBy { it.first }.map { it.second }
            if (lines.isEmpty()) continue
            totalMessages += lines.size
            val other = senders.firstOrNull { !it.equals(myName, ignoreCase = true) }
            val name = c.optStringOrNull("topic") ?: when (c.optString("chatType")) {
                "oneOnOne" -> if (other != null) "Chat with $other" else "1:1 chat"
                "meeting" -> "Meeting chat"
                else -> "Group chat"
            }
            chatTexts.add(name to lines.joinToString("\n"))
            // Things that look like they need you: messages from others that mention your first name.
            lines.filter { l ->
                val low = l.lowercase()
                firstName.length > 2 && low.contains(firstName) && !low.startsWith(myName.lowercase())
            }.take(2).forEach { actions.put(JSONObject().put("text", it.take(220)).put("source", name)) }
            perChat.put(JSONObject().put("name", name).put("count", lines.size))
        }
        diag.put("chatsWithMessages", perChat.length())
        diag.put("messages", totalMessages)

        // ---- summarise on the phone ----
        val (model, summaries) = summarise(ctx, chatTexts)
        for (i in 0 until perChat.length()) perChat.getJSONObject(i).put("points", JSONArray(summaries.getOrElse(i) { emptyList() }))
        val highlights = JSONArray()
        (0 until perChat.length()).map { perChat.getJSONObject(it) }
            .sortedByDescending { it.optInt("count") }
            .take(3)
            .forEach { ch -> ch.optJSONArray("points")?.optString(0)?.takeIf { it.isNotBlank() }?.let { highlights.put("${ch.optString("name")}: $it") } }
        diag.put("model", model)
        diag.put("seconds", (System.currentTimeMillis() - started) / 1000)

        return JSONObject()
            .put("date", day.toString())
            .put("generatedAt", System.currentTimeMillis())
            .put("account", username)
            .put("highlights", highlights)
            .put("actions", actions)
            .put("chats", perChat)
            .put("diagnostics", diag)
    }

    /** Gemini Nano (ML Kit GenAI) when the phone offers it; otherwise a simple no-AI digest. */
    private fun summarise(ctx: Context, chats: List<Pair<String, String>>): Pair<String, List<List<String>>> {
        if (chats.isEmpty()) return "none" to emptyList()
        val summarizer = runCatching {
            Summarization.getClient(
                SummarizerOptions.builder(ctx)
                    .setInputType(SummarizerOptions.InputType.CONVERSATION)
                    .setOutputType(SummarizerOptions.OutputType.THREE_BULLETS)
                    .setLanguage(SummarizerOptions.Language.ENGLISH)
                    .setLongInputAutoTruncationEnabled(true)
                    .build()
            )
        }.getOrNull()
        try {
            val status = summarizer?.let { runCatching { it.checkFeatureStatus().get() }.getOrNull() }
            if (summarizer != null && status == FeatureStatus.DOWNLOADABLE) {
                // One-time system download of the Gemini Nano feature (managed by Android, not stored in DayMate).
                runCatching { summarizer.downloadFeature(object : com.google.mlkit.genai.common.DownloadCallback {
                    override fun onDownloadStarted(bytesToDownload: Long) {}
                    override fun onDownloadProgress(totalBytesDownloaded: Long) {}
                    override fun onDownloadCompleted() {}
                    override fun onDownloadFailed(e: com.google.mlkit.genai.common.GenAiException) {}
                }).get() }
            }
            val ready = summarizer != null && runCatching { summarizer.checkFeatureStatus().get() }.getOrNull() == FeatureStatus.AVAILABLE
            if (ready) {
                val out = chats.map { (_, text) ->
                    runCatching { summarizer!!.runInference(SummarizationRequest.builder(text.take(12_000)).build()).get().summary }
                        .getOrNull()?.let(::bullets) ?: fallback(text)
                }
                return "Gemini Nano (on this phone)" to out
            }
            return "Simple digest (Gemini Nano not available)" to chats.map { fallback(it.second) }
        } finally {
            runCatching { summarizer?.close() }
        }
    }

    private fun bullets(s: String): List<String> = s.lines()
        .map { it.trim().trimStart('*', '-', '•', ' ') }
        .filter { it.isNotBlank() }
        .take(3)

    /** No-AI fallback: the last few substantial messages, shortened. */
    private fun fallback(text: String): List<String> = text.lines()
        .filter { it.substringAfter(": ").length > 20 }
        .takeLast(3)
        .map { if (it.length > 160) it.take(157) + "…" else it }
}
