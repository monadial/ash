package com.monadial.ash.ui.viewmodels

import app.cash.turbine.test
import com.google.common.truth.Truth.assertThat
import com.monadial.ash.TestFixtures
import com.monadial.ash.core.common.AppError
import com.monadial.ash.core.common.AppResult
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.repositories.ConversationRepository
import com.monadial.ash.domain.repositories.PadRepository
import com.monadial.ash.domain.usecases.conversation.BurnConversationUseCase
import com.monadial.ash.domain.usecases.conversation.CheckBurnStatusUseCase
import com.monadial.ash.domain.usecases.conversation.GetConversationsUseCase
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
@DisplayName("ConversationsViewModel")
class ConversationsViewModelTest {

    private val testDispatcher = StandardTestDispatcher()

    private lateinit var getConversationsUseCase: GetConversationsUseCase
    private lateinit var burnConversationUseCase: BurnConversationUseCase
    private lateinit var checkBurnStatusUseCase: CheckBurnStatusUseCase
    private lateinit var conversationRepository: ConversationRepository
    private lateinit var padRepository: PadRepository

    private val conversationsFlow = MutableStateFlow<List<Conversation>>(emptyList())

    @BeforeEach
    fun setup() {
        Dispatchers.setMain(testDispatcher)

        getConversationsUseCase = mockk(relaxed = true)
        burnConversationUseCase = mockk(relaxed = true)
        checkBurnStatusUseCase = mockk(relaxed = true)
        conversationRepository = mockk(relaxed = true)
        padRepository = mockk(relaxed = true)

        every { getConversationsUseCase.conversations } returns conversationsFlow
        coEvery { getConversationsUseCase() } returns AppResult.Success(emptyList())
    }

    @AfterEach
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createViewModel() = ConversationsViewModel(
        getConversationsUseCase = getConversationsUseCase,
        burnConversationUseCase = burnConversationUseCase,
        checkBurnStatusUseCase = checkBurnStatusUseCase,
        conversationRepository = conversationRepository,
        padRepository = padRepository
    )

    @Nested
    @DisplayName("initialization")
    inner class InitializationTests {

        @Test
        @DisplayName("should load conversations on initialization")
        fun loadsConversationsOnInit() = runTest {
            // Given
            val conversations = TestFixtures.createMultipleConversations(3)
            conversationsFlow.value = conversations
            coEvery { getConversationsUseCase() } returns AppResult.Success(conversations)

            // When
            val viewModel = createViewModel()
            advanceUntilIdle()

            // Then
            assertThat(viewModel.conversations.value).hasSize(3)
            coVerify { getConversationsUseCase() }
        }

        @Test
        @DisplayName("should set error when loading fails")
        fun setsErrorOnLoadFailure() = runTest {
            // Given
            coEvery { getConversationsUseCase() } returns
                AppResult.Error(AppError.Storage.ReadFailed("Database error"))

            // When
            val viewModel = createViewModel()
            advanceUntilIdle()

            // Then
            assertThat(viewModel.error.value).contains("Database error")
        }
    }

    @Nested
    @DisplayName("refresh()")
    inner class RefreshTests {

        @Test
        @DisplayName("should set isRefreshing during refresh")
        fun setsIsRefreshingDuringRefresh() = runTest {
            // Given
            val viewModel = createViewModel()
            advanceUntilIdle()
            coEvery { getConversationsUseCase.refresh() } returns AppResult.Success(emptyList())

            // When
            viewModel.isRefreshing.test {
                assertThat(awaitItem()).isFalse() // Initial state

                viewModel.refresh()
                assertThat(awaitItem()).isTrue() // Refreshing started

                advanceUntilIdle()
                assertThat(awaitItem()).isFalse() // Refreshing completed
            }
        }

        @Test
        @DisplayName("should check burn status for all conversations during refresh")
        fun checksBurnStatusOnRefresh() = runTest {
            // Given
            val conversations = TestFixtures.createMultipleConversations(2)
            conversationsFlow.value = conversations
            coEvery { getConversationsUseCase() } returns AppResult.Success(conversations)
            coEvery { getConversationsUseCase.refresh() } returns AppResult.Success(conversations)

            val viewModel = createViewModel()
            advanceUntilIdle()

            // When
            viewModel.refresh()
            advanceUntilIdle()

            // Then
            coVerify { checkBurnStatusUseCase.checkAll(conversations) }
        }

        @Test
        @DisplayName("should not check burn status when no conversations")
        fun skipsBurnStatusWhenEmpty() = runTest {
            // Given
            conversationsFlow.value = emptyList()
            coEvery { getConversationsUseCase() } returns AppResult.Success(emptyList())
            coEvery { getConversationsUseCase.refresh() } returns AppResult.Success(emptyList())

            val viewModel = createViewModel()
            advanceUntilIdle()

            // When
            viewModel.refresh()
            advanceUntilIdle()

            // Then
            coVerify(exactly = 0) { checkBurnStatusUseCase.checkAll(any()) }
        }
    }

    @Nested
    @DisplayName("burnConversation()")
    inner class BurnConversationTests {

        @Test
        @DisplayName("should burn conversation successfully")
        fun burnsConversationSuccessfully() = runTest {
            // Given
            val conversation = TestFixtures.createConversation()
            conversationsFlow.value = listOf(conversation)
            coEvery { getConversationsUseCase() } returns AppResult.Success(listOf(conversation))
            coEvery { burnConversationUseCase(conversation) } returns AppResult.Success(Unit)

            val viewModel = createViewModel()
            advanceUntilIdle()

            // When
            viewModel.burnConversation(conversation)
            advanceUntilIdle()

            // Then
            coVerify { burnConversationUseCase(conversation) }
            assertThat(viewModel.error.value).isNull()
        }

        @Test
        @DisplayName("should set error when burn fails")
        fun setsErrorOnBurnFailure() = runTest {
            // Given
            val conversation = TestFixtures.createConversation()
            coEvery { getConversationsUseCase() } returns AppResult.Success(listOf(conversation))
            coEvery { burnConversationUseCase(conversation) } returns
                AppResult.Error(AppError.Storage.WriteFailed("Burn failed"))

            val viewModel = createViewModel()
            advanceUntilIdle()

            // When
            viewModel.burnConversation(conversation)
            advanceUntilIdle()

            // Then
            assertThat(viewModel.error.value).contains("Failed to burn conversation")
        }
    }

    @Nested
    @DisplayName("deleteConversation()")
    inner class DeleteConversationTests {

        @Test
        @DisplayName("should wipe pad and delete conversation")
        fun wipesAndDeletes() = runTest {
            // Given
            val conversationId = "test-conversation-id"
            coEvery { getConversationsUseCase() } returns AppResult.Success(emptyList())

            val viewModel = createViewModel()
            advanceUntilIdle()

            // When
            viewModel.deleteConversation(conversationId)
            advanceUntilIdle()

            // Then
            coVerify { padRepository.wipePad(conversationId) }
            coVerify { conversationRepository.deleteConversation(conversationId) }
        }
    }

    @Nested
    @DisplayName("clearError()")
    inner class ClearErrorTests {

        @Test
        @DisplayName("should clear error state")
        fun clearsError() = runTest {
            // Given
            coEvery { getConversationsUseCase() } returns
                AppResult.Error(AppError.Storage.ReadFailed("Some error"))

            val viewModel = createViewModel()
            advanceUntilIdle()

            assertThat(viewModel.error.value).isNotNull()

            // When
            viewModel.clearError()

            // Then
            assertThat(viewModel.error.value).isNull()
        }
    }
}
