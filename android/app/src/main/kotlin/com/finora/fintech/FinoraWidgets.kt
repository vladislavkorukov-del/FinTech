package com.finora.fintech

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import java.io.File

/**
 * Home-screen widgets with Finora (1.27). The app writes the numbers and a
 * picture of Finora in her current mood (see FinoraBridge.saveWidgets); the
 * widgets only show them and open the app with an action.
 */
object FinoraWidgets {
    private val kinds = listOf(
        FinoraWidgetSmall::class.java,
        FinoraWidgetWide::class.java,
        FinoraWidgetPayments::class.java,
    )

    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (kind in kinds) {
            val ids = manager.getAppWidgetIds(ComponentName(context, kind))
            for (id in ids) update(context, manager, id, kind)
        }
    }

    fun update(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        kind: Class<*>,
    ) {
        val prefs = context.getSharedPreferences(FinoraBridge.PREFS, Context.MODE_PRIVATE)
        fun value(key: String, fallback: String = "") = prefs.getString(key, fallback) ?: fallback
        val views = when (kind) {
            FinoraWidgetSmall::class.java -> RemoteViews(context.packageName, R.layout.widget_small).apply {
                setTextViewText(R.id.widget_balance, value("balance", "—"))
                setTextViewText(R.id.widget_say, value("say", "Нажмите, чтобы сказать"))
                setOnClickPendingIntent(R.id.widget_root, FinoraBridge.launch(context, "voice", 10 + id))
            }
            FinoraWidgetWide::class.java -> RemoteViews(context.packageName, R.layout.widget_wide).apply {
                setTextViewText(R.id.widget_balance, value("balance", "—"))
                setTextViewText(R.id.widget_month, value("month", ""))
                setTextViewText(R.id.widget_income, value("income", ""))
                setTextViewText(R.id.widget_expense, value("expense", ""))
                setTextViewText(R.id.widget_say, value("say", ""))
                setOnClickPendingIntent(R.id.widget_root, FinoraBridge.launch(context, "open", 20 + id))
                setOnClickPendingIntent(R.id.widget_voice, FinoraBridge.launch(context, "voice", 30 + id))
                setOnClickPendingIntent(R.id.widget_add, FinoraBridge.launch(context, "expense", 40 + id))
                setOnClickPendingIntent(R.id.widget_scan, FinoraBridge.launch(context, "scan", 50 + id))
            }
            else -> RemoteViews(context.packageName, R.layout.widget_payments).apply {
                setTextViewText(R.id.widget_title, value("paymentsTitle", "Ближайшие платежи"))
                setTextViewText(R.id.widget_payments, value("payments", "Платежей нет"))
                setOnClickPendingIntent(R.id.widget_root, FinoraBridge.launch(context, "payments", 60 + id))
            }
        }
        val image = File(value(if (kind == FinoraWidgetPayments::class.java) "paymentsImage" else "image"))
        if (image.isFile) {
            val bitmap = BitmapFactory.decodeFile(image.path)
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.widget_finora, bitmap)
                views.setViewVisibility(R.id.widget_finora, View.VISIBLE)
            }
        }
        manager.updateAppWidget(id, views)
    }
}

open class FinoraWidgetBase : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) FinoraWidgets.update(context, manager, id, javaClass)
    }
}

/** 2×2: Finora, the balance; a tap — speak. */
class FinoraWidgetSmall : FinoraWidgetBase()

/** 4×2: Finora, balance, the month, and «Сказать» / «Расход» / «Скриншот». */
class FinoraWidgetWide : FinoraWidgetBase()

/** 4×2: the next payments; Finora worries when one is due. */
class FinoraWidgetPayments : FinoraWidgetBase()
