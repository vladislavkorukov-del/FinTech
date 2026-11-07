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

    /**
     * 1.36, like Duolingo's owl: Finora's mood on the main widgets comes
     * from the clock and the last day something was recorded — she is glad
     * when today is filled in, thoughtful in the morning, reminds in the
     * afternoon, gets angry in the evening and after days without records,
     * sleeps at night. A late payment beats everything. Worked out here, so
     * it changes while the app is closed (the widget wakes every 30 min).
     */
    fun mood(
        prefs: android.content.SharedPreferences,
        now: java.util.Calendar = java.util.Calendar.getInstance(),
    ): Pair<String, String> {
        fun value(key: String) = prefs.getString(key, "") ?: ""
        val alert = value("alert")
        val alertMood = value("alertMood")
        if (alert.isNotEmpty() && alertMood == "angry") return "angry" to alert
        val hour = now.get(java.util.Calendar.HOUR_OF_DAY)
        if (hour >= 23 || hour < 7) return "sleep" to "Zzz… Финора спит. Завтра запишем!"
        if (alert.isNotEmpty()) return "attention" to alert
        val today = String.format(
            java.util.Locale.ROOT,
            "%04d-%02d-%02d",
            now.get(java.util.Calendar.YEAR),
            now.get(java.util.Calendar.MONTH) + 1,
            now.get(java.util.Calendar.DAY_OF_MONTH),
        )
        val last = value("lastEntry")
        if (last == today) return "happy" to "Сегодня всё записано — умница!"
        val days = try {
            val f = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.ROOT)
            val a = f.parse(last)!!.time
            val b = f.parse(today)!!.time
            ((b - a) / 86_400_000L).toInt()
        } catch (_: Exception) {
            -1
        }
        if (days < 0) return "thinking" to "Расскажите, что сегодня потратили?"
        if (days >= 2) return "angry" to "Уже $days ${daysWord(days)} без записей! Я всё вижу 😤"
        return when {
            hour < 14 -> "thinking" to "Что сегодня потратили?"
            hour < 20 -> "attention" to "Не забудьте записать расходы и доходы"
            else -> "angry" to "Сегодня ничего не записано! Я жду 😤"
        }
    }

    private fun daysWord(n: Int): String {
        val last = n % 10
        val lastTwo = n % 100
        return when {
            last == 1 && lastTwo != 11 -> "день"
            last in 2..4 && (lastTwo < 12 || lastTwo > 14) -> "дня"
            else -> "дней"
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
        val (mood, line) = mood(prefs)
        val views = when (kind) {
            FinoraWidgetSmall::class.java -> RemoteViews(context.packageName, R.layout.widget_small).apply {
                setTextViewText(R.id.widget_balance, value("balance", "—"))
                setTextViewText(R.id.widget_say, line)
                setOnClickPendingIntent(R.id.widget_root, FinoraBridge.launch(context, "voice", 10 + id))
            }
            FinoraWidgetWide::class.java -> RemoteViews(context.packageName, R.layout.widget_wide).apply {
                setTextViewText(R.id.widget_balance, value("balance", "—"))
                setTextViewText(R.id.widget_month, value("month", ""))
                setTextViewText(R.id.widget_income, value("income", ""))
                setTextViewText(R.id.widget_expense, value("expense", ""))
                setTextViewText(R.id.widget_say, line)
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
        val moodImage = value("image_$mood")
        val image = File(
            when {
                kind == FinoraWidgetPayments::class.java -> value("paymentsImage")
                moodImage.isNotEmpty() -> moodImage
                else -> value("image")
            },
        )
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
