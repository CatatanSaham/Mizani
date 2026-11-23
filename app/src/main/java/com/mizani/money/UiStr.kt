package com.mizani.money

import android.content.Context

/** Global string lookup for non-composable code (data lists, try blocks, helpers). */
object UiStr {
    @Volatile
    lateinit var app: Context

    fun s(id: Int): String = app.getString(id)
}
