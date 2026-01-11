package com.monadial.ash.di

import com.monadial.ash.data.services.CryptoServiceImpl
import com.monadial.ash.data.services.RealtimeServiceImpl
import com.monadial.ash.data.services.RelayServiceImpl
import com.monadial.ash.domain.services.CryptoService
import com.monadial.ash.domain.services.RealtimeService
import com.monadial.ash.domain.services.RelayService
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * DI module for data layer service bindings.
 * Binds service interfaces to their implementations.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class DataModule {

    @Binds
    @Singleton
    abstract fun bindRelayService(impl: RelayServiceImpl): RelayService

    @Binds
    @Singleton
    abstract fun bindCryptoService(impl: CryptoServiceImpl): CryptoService

    @Binds
    @Singleton
    abstract fun bindRealtimeService(impl: RealtimeServiceImpl): RealtimeService
}
