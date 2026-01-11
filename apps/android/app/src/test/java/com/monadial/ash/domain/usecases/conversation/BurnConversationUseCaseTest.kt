package com.monadial.ash.domain.usecases.conversation

import com.google.common.truth.Truth.assertThat
import com.monadial.ash.TestFixtures
import com.monadial.ash.core.common.AppError
import com.monadial.ash.core.common.AppResult
import com.monadial.ash.domain.entities.Conversation
import com.monadial.ash.domain.repositories.ConversationRepository
import com.monadial.ash.domain.repositories.PadRepository
import com.monadial.ash.domain.services.RelayService
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

@DisplayName("BurnConversationUseCase")
class BurnConversationUseCaseTest {

    private lateinit var relayService: RelayService
    private lateinit var conversationRepository: ConversationRepository
    private lateinit var padRepository: PadRepository
    private lateinit var useCase: BurnConversationUseCase

    @BeforeEach
    fun setup() {
        relayService = mockk(relaxed = true)
        conversationRepository = mockk(relaxed = true)
        padRepository = mockk(relaxed = true)
        useCase = BurnConversationUseCase(relayService, conversationRepository, padRepository)
    }

    @Nested
    @DisplayName("invoke()")
    inner class InvokeTests {

        @Test
        @DisplayName("should burn conversation successfully when all operations succeed")
        fun burnSuccessfully() = runTest {
            // Given
            val conversation = TestFixtures.createConversation()
            coEvery { relayService.burnConversation(any(), any(), any()) } returns AppResult.Success(Unit)
            coEvery { padRepository.wipePad(any()) } returns AppResult.Success(Unit)
            coEvery { conversationRepository.deleteConversation(any()) } returns AppResult.Success(Unit)

            // When
            val result = useCase(conversation)

            // Then
            assertThat(result.isSuccess).isTrue()
            coVerify { relayService.burnConversation(conversation.id, conversation.burnToken, conversation.relayUrl) }
            coVerify { padRepository.wipePad(conversation.id) }
            coVerify { conversationRepository.deleteConversation(conversation.id) }
        }

        @Test
        @DisplayName("should continue burn process even if relay notification fails")
        fun continueOnRelayFailure() = runTest {
            // Given
            val conversation = TestFixtures.createConversation()
            coEvery { relayService.burnConversation(any(), any(), any()) } throws Exception("Network error")
            coEvery { padRepository.wipePad(any()) } returns AppResult.Success(Unit)
            coEvery { conversationRepository.deleteConversation(any()) } returns AppResult.Success(Unit)

            // When
            val result = useCase(conversation)

            // Then
            assertThat(result.isSuccess).isTrue()
            coVerify { padRepository.wipePad(conversation.id) }
            coVerify { conversationRepository.deleteConversation(conversation.id) }
        }

        @Test
        @DisplayName("should return error when pad wipe fails")
        fun errorOnPadWipeFailure() = runTest {
            // Given
            val conversation = TestFixtures.createConversation()
            coEvery { relayService.burnConversation(any(), any(), any()) } returns AppResult.Success(Unit)
            coEvery { padRepository.wipePad(any()) } throws Exception("Storage error")

            // When
            val result = useCase(conversation)

            // Then
            assertThat(result.isError).isTrue()
            val error = result.errorOrNull()
            assertThat(error).isInstanceOf(AppError.Storage.WriteFailed::class.java)
        }

        @Test
        @DisplayName("should return error when conversation delete fails")
        fun errorOnDeleteFailure() = runTest {
            // Given
            val conversation = TestFixtures.createConversation()
            coEvery { relayService.burnConversation(any(), any(), any()) } returns AppResult.Success(Unit)
            coEvery { padRepository.wipePad(any()) } returns AppResult.Success(Unit)
            coEvery { conversationRepository.deleteConversation(any()) } throws Exception("Delete failed")

            // When
            val result = useCase(conversation)

            // Then
            assertThat(result.isError).isTrue()
        }
    }

    @Nested
    @DisplayName("burnAll()")
    inner class BurnAllTests {

        @Test
        @DisplayName("should return count of successfully burned conversations")
        fun burnAllSuccessfully() = runTest {
            // Given
            val conversations = TestFixtures.createMultipleConversations(3)
            coEvery { relayService.burnConversation(any(), any(), any()) } returns AppResult.Success(Unit)
            coEvery { padRepository.wipePad(any()) } returns AppResult.Success(Unit)
            coEvery { conversationRepository.deleteConversation(any()) } returns AppResult.Success(Unit)

            // When
            val burnedCount = useCase.burnAll(conversations)

            // Then
            assertThat(burnedCount).isEqualTo(3)
        }

        @Test
        @DisplayName("should count partial success when some burns fail")
        fun partialBurnSuccess() = runTest {
            // Given
            val conversations = TestFixtures.createMultipleConversations(3)
            coEvery { relayService.burnConversation(any(), any(), any()) } returns AppResult.Success(Unit)
            coEvery { padRepository.wipePad("conversation-1") } returns AppResult.Success(Unit)
            coEvery { padRepository.wipePad("conversation-2") } throws Exception("Failed")
            coEvery { padRepository.wipePad("conversation-3") } returns AppResult.Success(Unit)
            coEvery { conversationRepository.deleteConversation(any()) } returns AppResult.Success(Unit)

            // When
            val burnedCount = useCase.burnAll(conversations)

            // Then
            assertThat(burnedCount).isEqualTo(2)
        }

        @Test
        @DisplayName("should return zero when all burns fail")
        fun allBurnsFail() = runTest {
            // Given
            val conversations = TestFixtures.createMultipleConversations(3)
            coEvery { padRepository.wipePad(any()) } throws Exception("Storage error")

            // When
            val burnedCount = useCase.burnAll(conversations)

            // Then
            assertThat(burnedCount).isEqualTo(0)
        }

        @Test
        @DisplayName("should return zero for empty list")
        fun emptyList() = runTest {
            // When
            val burnedCount = useCase.burnAll(emptyList<Conversation>())

            // Then
            assertThat(burnedCount).isEqualTo(0)
        }
    }
}
