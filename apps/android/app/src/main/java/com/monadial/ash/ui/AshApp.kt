package com.monadial.ash.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.monadial.ash.ui.screens.CeremonyScreen
import com.monadial.ash.ui.screens.ConversationInfoScreen
import com.monadial.ash.ui.screens.ConversationsScreen
import com.monadial.ash.ui.screens.LockScreen
import com.monadial.ash.ui.screens.MessagingScreen
import com.monadial.ash.ui.screens.SettingsScreen
import com.monadial.ash.ui.viewmodels.AppViewModel

sealed class Screen(val route: String) {
    data object Lock : Screen("lock")

    data object Conversations : Screen("conversations")

    data object Messaging : Screen("messaging/{conversationId}") {
        fun createRoute(conversationId: String) = "messaging/$conversationId"
    }

    data object ConversationInfo : Screen("conversation-info/{conversationId}") {
        fun createRoute(conversationId: String) = "conversation-info/$conversationId"
    }

    data object Ceremony : Screen("ceremony")

    data object Settings : Screen("settings")
}

@Composable
fun AshApp(viewModel: AppViewModel = hiltViewModel()) {
    val isLocked by viewModel.isLocked.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()

    val navController = rememberNavController()

    val startDestination =
        when {
            isLoading -> Screen.Lock.route
            isLocked -> Screen.Lock.route
            else -> Screen.Conversations.route
        }

    NavHost(
        navController = navController,
        startDestination = startDestination
    ) {
        composable(Screen.Lock.route) {
            LockScreen(
                onUnlocked = {
                    navController.navigate(Screen.Conversations.route) {
                        popUpTo(Screen.Lock.route) { inclusive = true }
                    }
                }
            )
        }

        composable(Screen.Conversations.route) {
            ConversationsScreen(
                onConversationClick = { conversationId ->
                    navController.navigate(Screen.Messaging.createRoute(conversationId))
                },
                onNewConversation = {
                    navController.navigate(Screen.Ceremony.route)
                },
                onSettingsClick = {
                    navController.navigate(Screen.Settings.route)
                }
            )
        }

        composable(
            route = Screen.Messaging.route,
            arguments = listOf(navArgument("conversationId") { type = NavType.StringType })
        ) { backStackEntry ->
            val conversationId = backStackEntry.arguments?.getString("conversationId") ?: return@composable
            MessagingScreen(
                conversationId = conversationId,
                onBack = { navController.popBackStack() },
                onInfoClick = { navController.navigate(Screen.ConversationInfo.createRoute(conversationId)) }
            )
        }

        composable(
            route = Screen.ConversationInfo.route,
            arguments = listOf(navArgument("conversationId") { type = NavType.StringType })
        ) { backStackEntry ->
            val conversationId = backStackEntry.arguments?.getString("conversationId") ?: return@composable
            ConversationInfoScreen(
                conversationId = conversationId,
                onBack = { navController.popBackStack() },
                onBurned = {
                    navController.navigate(Screen.Conversations.route) {
                        popUpTo(Screen.Conversations.route) { inclusive = true }
                    }
                }
            )
        }

        composable(route = Screen.Ceremony.route) {
            CeremonyScreen(
                onComplete = { conversationId ->
                    navController.navigate(Screen.Messaging.createRoute(conversationId)) {
                        popUpTo(Screen.Conversations.route)
                    }
                },
                onCancel = { navController.popBackStack() }
            )
        }

        composable(Screen.Settings.route) {
            SettingsScreen(
                onBack = { navController.popBackStack() }
            )
        }
    }
}
