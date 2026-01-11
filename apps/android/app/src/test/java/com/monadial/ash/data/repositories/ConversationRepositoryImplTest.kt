package com.monadial.ash.data.repositories

import com.google.common.truth.Truth.assertThat
import com.monadial.ash.TestFixtures
import com.monadial.ash.core.common.AppError
import com.monadial.ash.core.services.ConversationStorageService
import com.monadial.ash.domain.entities.Conversation
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.just
import io.mockk.mockk
import io.mockk.runs
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

@DisplayName("ConversationRepositoryImpl")
class ConversationRepositoryImplTest {

    private lateinit var storageService: ConversationStorageService
    private lateinit var repository: ConversationRepositoryImpl

    private val conversationsFlow = MutableStateFlow<List<Conversation>>(emptyList())

    @BeforeEach
    fun setup() {
        storageService = mockk(relaxed = true)
        every { storageService.conversations } returns conversationsFlow
        repository = ConversationRepositoryImpl(storageService)
    }

    @Nested
    @DisplayName("conversations")
    inner class ConversationsPropertyTests {

        @Test
        @DisplayName("should delegate to storage service")
        fun delegatesToStorageService() {
            // Given
            val conversations = TestFixtures.createMultipleConversations(3)
            conversationsFlow.value = conversations

            // Then
            assertThat(repository.conversations.value).isEqualTo(conversations)
        }
    }

    @Nested
    @DisplayName("loadConversations()")
    inner class LoadConversationsTests {

        @Test
        @DisplayName("should return success with conversations list")
        fun returnsSuccessWithConversations() = runTest {
            // Given
            val conversations = TestFixtures.createMultipleConversations(3)
            conversationsFlow.value = conversations
            coEvery { storageService.loadConversations() } just runs

            // When
            val result = repository.loadConversations()

            // Then
            assertThat(result.isSuccess).isTrue()
            assertThat(result.getOrNull()).hasSize(3)
        }

        @Test
        @DisplayName("should return error when storage throws exception")
        fun returnsErrorOnException() = runTest {
            // Given
            coEvery { storageService.loadConversations() } throws RuntimeException("Storage error")

            // When
            val result = repository.loadConversations()

            // Then
            assertThat(result.isError).isTrue()
            val error = result.errorOrNull()
            assertThat(error).isInstanceOf(AppError.Storage.ReadFailed::class.java)
        }
    }

    @Nested
    @DisplayName("getConversation()")
    inner class GetConversationTests {

        @Test
        @DisplayName("should return success when conversation exists")
        fun returnsSuccessWhenExists() = runTest {
            // Given
            val conversation = TestFixtures.createConversation(id = "test-id")
            coEvery { storageService.getConversation("test-id") } returns conversation

            // When
            val result = repository.getConversation("test-id")

            // Then
            assertThat(result.isSuccess).isTrue()
            assertThat(result.getOrNull()).isEqualTo(conversation)
        }

        @Test
        @DisplayName("should return NotFound error when conversation doesn't exist")
        fun returnsNotFoundWhenMissing() = runTest {
            // Given
            coEvery { storageService.getConversation("nonexistent") } returns null

            // When
            val result = repository.getConversation("nonexistent")

            // Then
            assertThat(result.isError).isTrue()
            val error = result.errorOrNull()
            assertThat(error).isInstanceOf(AppError.Storage.NotFound::class.java)
        }

        @Test
        @DisplayName("should return error when storage throws exception")
        fun returnsErrorOnException() = runTest {
            // Given
            coEvery { storageService.getConversation(any()) } throws RuntimeException("Error")

            // When
            val result = repository.getConversation("test-id")

            // Then
            assertThat(result.isError).isTrue()
            val error = result.errorOrNull()
            assertThat(error).isInstanceOf(AppError.Storage.ReadFailed::class.java)
        }
    }

    @Nested
    @DisplayName("saveConversation()")
    inner class SaveConversationTests {

        @Test
        @DisplayName("should save conversation successfully")
        fun savesSuccessfully() = runTest {
            // Given
            val conversation = TestFixtures.createConversation()
            coEvery { storageService.saveConversation(conversation) } just runs

            // When
            val result = repository.saveConversation(conversation)

            // Then
            assertThat(result.isSuccess).isTrue()
            coVerify { storageService.saveConversation(conversation) }
        }

        @Test
        @DisplayName("should return error when storage throws exception")
        fun returnsErrorOnException() = runTest {
            // Given
            val conversation = TestFixtures.createConversation()
            coEvery { storageService.saveConversation(any()) } throws RuntimeException("Save failed")

            // When
            val result = repository.saveConversation(conversation)

            // Then
            assertThat(result.isError).isTrue()
            val error = result.errorOrNull()
            assertThat(error).isInstanceOf(AppError.Storage.WriteFailed::class.java)
        }
    }

    @Nested
    @DisplayName("deleteConversation()")
    inner class DeleteConversationTests {

        @Test
        @DisplayName("should delete conversation successfully")
        fun deletesSuccessfully() = runTest {
            // Given
            coEvery { storageService.deleteConversation("test-id") } just runs

            // When
            val result = repository.deleteConversation("test-id")

            // Then
            assertThat(result.isSuccess).isTrue()
            coVerify { storageService.deleteConversation("test-id") }
        }

        @Test
        @DisplayName("should return error when storage throws exception")
        fun returnsErrorOnException() = runTest {
            // Given
            coEvery { storageService.deleteConversation(any()) } throws RuntimeException("Delete failed")

            // When
            val result = repository.deleteConversation("test-id")

            // Then
            assertThat(result.isError).isTrue()
            val error = result.errorOrNull()
            assertThat(error).isInstanceOf(AppError.Storage.WriteFailed::class.java)
        }
    }

    @Nested
    @DisplayName("updateConversation()")
    inner class UpdateConversationTests {

        @Test
        @DisplayName("should update and return updated conversation")
        fun updatesSuccessfully() = runTest {
            // Given
            val original = TestFixtures.createConversation(id = "test-id", name = "Original")
            coEvery { storageService.getConversation("test-id") } returns original
            coEvery { storageService.saveConversation(any()) } just runs

            // When
            val result = repository.updateConversation("test-id") { it.renamed("Updated") }

            // Then
            assertThat(result.isSuccess).isTrue()
            val updated = result.getOrNull()!!
            assertThat(updated.name).isEqualTo("Updated")
        }

        @Test
        @DisplayName("should return NotFound when conversation doesn't exist")
        fun returnsNotFoundWhenMissing() = runTest {
            // Given
            coEvery { storageService.getConversation("nonexistent") } returns null

            // When
            val result = repository.updateConversation("nonexistent") { it }

            // Then
            assertThat(result.isError).isTrue()
            val error = result.errorOrNull()
            assertThat(error).isInstanceOf(AppError.Storage.NotFound::class.java)
        }
    }

    @Nested
    @DisplayName("updateLastMessage()")
    inner class UpdateLastMessageTests {

        @Test
        @DisplayName("should update last message preview and timestamp")
        fun updatesLastMessage() = runTest {
            // Given
            val conversation = TestFixtures.createConversation(id = "test-id")
            coEvery { storageService.getConversation("test-id") } returns conversation
            coEvery { storageService.saveConversation(any()) } just runs

            // When
            val result = repository.updateLastMessage("test-id", "New preview", 12345L)

            // Then
            assertThat(result.isSuccess).isTrue()
            coVerify {
                storageService.saveConversation(match {
                    it.lastMessagePreview == "New preview" && it.lastMessageAt == 12345L
                })
            }
        }
    }

    @Nested
    @DisplayName("markPeerBurned()")
    inner class MarkPeerBurnedTests {

        @Test
        @DisplayName("should mark conversation as burned by peer")
        fun marksBurnedSuccessfully() = runTest {
            // Given
            val conversation = TestFixtures.createConversation(id = "test-id", peerBurnedAt = null)
            coEvery { storageService.getConversation("test-id") } returns conversation
            coEvery { storageService.saveConversation(any()) } just runs
            val burnTimestamp = System.currentTimeMillis()

            // When
            val result = repository.markPeerBurned("test-id", burnTimestamp)

            // Then
            assertThat(result.isSuccess).isTrue()
            coVerify {
                storageService.saveConversation(match { it.peerBurnedAt == burnTimestamp })
            }
        }
    }

    @Nested
    @DisplayName("updatePadConsumption()")
    inner class UpdatePadConsumptionTests {

        @Test
        @DisplayName("should update pad consumption values")
        fun updatesPadConsumption() = runTest {
            // Given
            val conversation = TestFixtures.createConversation(
                id = "test-id",
                padConsumedFront = 0,
                padConsumedBack = 0
            )
            coEvery { storageService.getConversation("test-id") } returns conversation
            coEvery { storageService.saveConversation(any()) } just runs

            // When
            val result = repository.updatePadConsumption("test-id", 1000L, 500L)

            // Then
            assertThat(result.isSuccess).isTrue()
            coVerify {
                storageService.saveConversation(match {
                    it.padConsumedFront == 1000L && it.padConsumedBack == 500L
                })
            }
        }
    }
}
