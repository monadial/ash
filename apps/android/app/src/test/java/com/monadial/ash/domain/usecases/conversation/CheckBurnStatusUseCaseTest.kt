package com.monadial.ash.domain.usecases.conversation

import com.google.common.truth.Truth.assertThat
import com.monadial.ash.TestFixtures
import com.monadial.ash.core.common.AppError
import com.monadial.ash.core.common.AppResult
import com.monadial.ash.core.services.BurnStatusResponse
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.repositories.ConversationRepository
import com.monadial.ash.domain.services.RelayService
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

@DisplayName("CheckBurnStatusUseCase")
class CheckBurnStatusUseCaseTest {

    private lateinit var relayService: RelayService
    private lateinit var conversationRepository: ConversationRepository
    private lateinit var useCase: CheckBurnStatusUseCase

    @BeforeEach
    fun setup() {
        relayService = mockk(relaxed = true)
        conversationRepository = mockk(relaxed = true)
        useCase = CheckBurnStatusUseCase(relayService, conversationRepository)
    }

    @Nested
    @DisplayName("invoke()")
    inner class InvokeTests {

        @Test
        @DisplayName("should return not burned when conversation is active")
        fun notBurned() = runTest {
            // Given
            val conversation = TestFixtures.createConversation()
            coEvery {
                relayService.checkBurnStatus(any(), any(), any())
            } returns AppResult.Success(BurnStatusResponse(burned = false, burnedAt = null))

            // When
            val result = useCase(conversation)

            // Then
            assertThat(result.isSuccess).isTrue()
            val status = result.getOrNull()!!
            assertThat(status.burned).isFalse()
            assertThat(status.conversationUpdated).isFalse()
        }

        @Test
        @DisplayName("should return burned and update local state when peer has burned")
        fun burnedAndUpdated() = runTest {
            // Given
            val conversation = TestFixtures.createConversation(peerBurnedAt = null)
            coEvery {
                relayService.checkBurnStatus(any(), any(), any())
            } returns AppResult.Success(BurnStatusResponse(burned = true, burnedAt = "2024-01-01T00:00:00Z"))
            coEvery { conversationRepository.saveConversation(any()) } returns AppResult.Success(Unit)

            // When
            val result = useCase(conversation)

            // Then
            assertThat(result.isSuccess).isTrue()
            val status = result.getOrNull()!!
            assertThat(status.burned).isTrue()
            assertThat(status.burnedAt).isEqualTo("2024-01-01T00:00:00Z")
            assertThat(status.conversationUpdated).isTrue()
            coVerify { conversationRepository.saveConversation(match { it.peerBurnedAt != null }) }
        }

        @Test
        @DisplayName("should not update when already marked as burned locally")
        fun alreadyMarkedBurned() = runTest {
            // Given
            val conversation = TestFixtures.createConversation(peerBurnedAt = System.currentTimeMillis())
            coEvery {
                relayService.checkBurnStatus(any(), any(), any())
            } returns AppResult.Success(BurnStatusResponse(burned = true, burnedAt = "2024-01-01T00:00:00Z"))

            // When
            val result = useCase(conversation)

            // Then
            assertThat(result.isSuccess).isTrue()
            val status = result.getOrNull()!!
            assertThat(status.burned).isTrue()
            assertThat(status.conversationUpdated).isFalse()
            coVerify(exactly = 0) { conversationRepository.saveConversation(any()) }
        }

        @Test
        @DisplayName("should not update when updateIfBurned is false")
        fun skipUpdateWhenFlagFalse() = runTest {
            // Given
            val conversation = TestFixtures.createConversation(peerBurnedAt = null)
            coEvery {
                relayService.checkBurnStatus(any(), any(), any())
            } returns AppResult.Success(BurnStatusResponse(burned = true, burnedAt = "2024-01-01T00:00:00Z"))

            // When
            val result = useCase(conversation, updateIfBurned = false)

            // Then
            assertThat(result.isSuccess).isTrue()
            val status = result.getOrNull()!!
            assertThat(status.burned).isTrue()
            assertThat(status.conversationUpdated).isFalse()
            coVerify(exactly = 0) { conversationRepository.saveConversation(any()) }
        }

        @Test
        @DisplayName("should return error when relay check fails")
        fun relayError() = runTest {
            // Given
            val conversation = TestFixtures.createConversation()
            coEvery {
                relayService.checkBurnStatus(any(), any(), any())
            } returns AppResult.Error(AppError.Network.ConnectionFailed("Network error"))

            // When
            val result = useCase(conversation)

            // Then
            assertThat(result.isError).isTrue()
            val error = result.errorOrNull()
            assertThat(error).isInstanceOf(AppError.Network.ConnectionFailed::class.java)
        }
    }

    @Nested
    @DisplayName("checkAll()")
    inner class CheckAllTests {

        @Test
        @DisplayName("should check all conversations and return map of results")
        fun checkAllConversations() = runTest {
            // Given
            val conversations = TestFixtures.createMultipleConversations(3)
            coEvery {
                relayService.checkBurnStatus("conversation-1", any(), any())
            } returns AppResult.Success(BurnStatusResponse(burned = false))
            coEvery {
                relayService.checkBurnStatus("conversation-2", any(), any())
            } returns AppResult.Success(BurnStatusResponse(burned = true, burnedAt = "2024-01-01"))
            coEvery {
                relayService.checkBurnStatus("conversation-3", any(), any())
            } returns AppResult.Error(AppError.Network.ConnectionFailed("Error"))
            coEvery { conversationRepository.saveConversation(any()) } returns AppResult.Success(Unit)

            // When
            val results = useCase.checkAll(conversations)

            // Then
            assertThat(results).hasSize(3)
            assertThat(results["conversation-1"]?.isSuccess).isTrue()
            assertThat(results["conversation-1"]?.getOrNull()?.burned).isFalse()
            assertThat(results["conversation-2"]?.isSuccess).isTrue()
            assertThat(results["conversation-2"]?.getOrNull()?.burned).isTrue()
            assertThat(results["conversation-3"]?.isError).isTrue()
        }

        @Test
        @DisplayName("should return empty map for empty list")
        fun emptyList() = runTest {
            // When
            val results = useCase.checkAll(emptyList<Conversation>())

            // Then
            assertThat(results).isEmpty()
        }
    }
}
