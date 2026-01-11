package com.monadial.ash.core.common

/**
 * A sealed class representing the result of an operation that can either succeed or fail.
 * Provides functional operators for composing operations.
 */
sealed class AppResult<out T> {
    data class Success<T>(val data: T) : AppResult<T>()
    data class Error(val error: AppError) : AppResult<Nothing>()

    val isSuccess: Boolean get() = this is Success
    val isError: Boolean get() = this is Error

    fun getOrNull(): T? = (this as? Success)?.data
    fun errorOrNull(): AppError? = (this as? Error)?.error

    fun getOrThrow(): T = when (this) {
        is Success -> data
        is Error -> throw error.toException()
    }

    inline fun <R> map(transform: (T) -> R): AppResult<R> = when (this) {
        is Success -> Success(transform(data))
        is Error -> this
    }

    inline fun <R> flatMap(transform: (T) -> AppResult<R>): AppResult<R> = when (this) {
        is Success -> transform(data)
        is Error -> this
    }

    inline fun onSuccess(action: (T) -> Unit): AppResult<T> {
        if (this is Success) action(data)
        return this
    }

    inline fun onError(action: (AppError) -> Unit): AppResult<T> {
        if (this is Error) action(error)
        return this
    }

    inline fun recover(transform: (AppError) -> @UnsafeVariance T): T = when (this) {
        is Success -> data
        is Error -> transform(error)
    }

    inline fun recoverWith(transform: (AppError) -> AppResult<@UnsafeVariance T>): AppResult<T> = when (this) {
        is Success -> this
        is Error -> transform(error)
    }

    companion object {
        fun <T> success(data: T): AppResult<T> = Success(data)
        fun <T> error(error: AppError): AppResult<T> = Error(error)
        fun <T> error(message: String): AppResult<T> = Error(AppError.Unknown(message))

        inline fun <T> runCatching(block: () -> T): AppResult<T> = try {
            Success(block())
        } catch (e: Exception) {
            Error(AppError.fromException(e))
        }

        suspend inline fun <T> runCatchingSuspend(crossinline block: suspend () -> T): AppResult<T> = try {
            Success(block())
        } catch (e: Exception) {
            Error(AppError.fromException(e))
        }
    }
}

/**
 * Combines two results, returning a pair if both succeed.
 */
fun <A, B> AppResult<A>.zip(other: AppResult<B>): AppResult<Pair<A, B>> = flatMap { a ->
    other.map { b -> a to b }
}

/**
 * Extension to convert Kotlin Result to AppResult.
 */
fun <T> Result<T>.toAppResult(): AppResult<T> = fold(
    onSuccess = { AppResult.Success(it) },
    onFailure = { AppResult.Error(AppError.fromException(it)) }
)
