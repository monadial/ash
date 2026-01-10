package com.monadial.ash

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class AshApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        // Load native library
        System.loadLibrary("ash_bindings")
    }
}
