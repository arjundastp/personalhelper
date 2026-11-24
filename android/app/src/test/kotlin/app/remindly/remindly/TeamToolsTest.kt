package app.remindly.remindly

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TeamToolsTest {
    @Test fun readToolsAllowed() {
        listOf(
            "ListChats", "ListChatMessages", "GetChatMessage", "ListTeams", "ListChannels",
            "ListChannelMessages", "mcp_graph_chat_listChatMessages", "SearchTeamsMessages", "GetChat",
        ).forEach { assertTrue(it, Team.isReadOnlyTool(it)) }
    }

    @Test fun writeToolsBlocked() {
        listOf(
            "PostMessage", "SendMessageToSelf", "PostChannelMessage", "UpdateChatMessage", "DeleteChatMessage",
            "ReplyToChannelMessage", "CreateChat", "AddChatMember", "RemoveChatMember", "UpdateChat",
            "mcp_graph_chat_postMessage", "SetChatTopic", "GetAndDeleteMessage", "doSomething",
        ).forEach { assertFalse(it, Team.isReadOnlyTool(it)) }
    }
}
