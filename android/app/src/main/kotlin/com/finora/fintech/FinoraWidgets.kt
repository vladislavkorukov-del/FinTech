package com.finora.fintech

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.view.View
import android.widget.RemoteViews

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
        FinoraWidgetBuddy::class.java,
        FinoraWidgetSticker::class.java,
        FinoraWidgetMini::class.java,
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
            Math.round((b - a) / 86_400_000.0).toInt()
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

    /**
     * 1.40: which of Finora's pictures to show. The app passes the picture
     * for the data («tile»); here the clock and payments come first.
     */
    fun picture(
        prefs: android.content.SharedPreferences,
        now: java.util.Calendar = java.util.Calendar.getInstance(),
    ): Int = resource(pictureName(prefs, now))

    fun pictureName(
        prefs: android.content.SharedPreferences,
        now: java.util.Calendar = java.util.Calendar.getInstance(),
    ): String {
        fun value(key: String) = prefs.getString(key, "") ?: ""
        val hour = now.get(java.util.Calendar.HOUR_OF_DAY)
        val days = daysSince(value("lastEntry"), now)
        val dayOfYear = now.get(java.util.Calendar.DAY_OF_YEAR)
        val name = when {
            value("payState") == "overdue" -> "pay_dont_forget"
            value("payState") == "today" -> "payment_today"
            hour >= 23 || hour < 7 -> "calm"
            // 1.41: nothing recorded today — four pictures in turn; in the
            // evening the louder one.
            days != 0 && hour >= 19 -> "record_due_blue"
            days != 0 && hour >= 11 -> listOf(
                "record_expense",
                "record_expense_lilac",
                "record_due_groceries",
            )[dayOfYear % 3]
            value("payState") == "soon" -> "payment_reminder"
            else -> value("tile").ifEmpty { "check" }
        }
        return name
    }

    /** 1.42: a juicy background in the colour of the picture. */
    fun background(name: String): Int = when (name) {
        "budget_month", "limit_today", "record_expense_lilac",
        "record_due_groceries", "expenses_today",
        -> R.drawable.widget_vivid_violet
        "income_tracking", "goal_month", "dream_savings" -> R.drawable.widget_vivid_mint
        "pay_dont_forget", "payment_reminder", "record_due_blue" -> R.drawable.widget_vivid_blue
        "budget_month_pink", "plan_budget" -> R.drawable.widget_vivid_pink
        "limit", "growing", "budget_topup" -> R.drawable.widget_vivid_red
        else -> R.drawable.widget_vivid_teal
    }

    /** 1.41: the owner's 25 pictures of Finora. */
    fun resource(name: String): Int = when (name) {
        "budget_month" -> R.drawable.finora_mood_budget_month
        "budget_month_pink" -> R.drawable.finora_mood_budget_month_pink
        "budget_topup" -> R.drawable.finora_mood_budget_topup
        "calm" -> R.drawable.finora_mood_calm
        "dream_savings" -> R.drawable.finora_mood_dream_savings
        "expenses_today" -> R.drawable.finora_mood_expenses_today
        "forward" -> R.drawable.finora_mood_forward
        "goal_month" -> R.drawable.finora_mood_goal_month
        "growing" -> R.drawable.finora_mood_growing
        "income" -> R.drawable.finora_mood_income
        "income_tracking" -> R.drawable.finora_mood_income_tracking
        "limit" -> R.drawable.finora_mood_limit
        "limit_today" -> R.drawable.finora_mood_limit_today
        "pay_dont_forget" -> R.drawable.finora_mood_pay_dont_forget
        "payment_reminder" -> R.drawable.finora_mood_payment_reminder
        "payment_today" -> R.drawable.finora_mood_payment_today
        "piggy" -> R.drawable.finora_mood_piggy
        "plan_budget" -> R.drawable.finora_mood_plan_budget
        "plus" -> R.drawable.finora_mood_plus
        "record_due_blue" -> R.drawable.finora_mood_record_due_blue
        "record_due_groceries" -> R.drawable.finora_mood_record_due_groceries
        "record_expense" -> R.drawable.finora_mood_record_expense
        "record_expense_lilac" -> R.drawable.finora_mood_record_expense_lilac
        "saving" -> R.drawable.finora_mood_saving
        else -> R.drawable.finora_mood_check
    }

    /** Days from [last] (yyyy-MM-dd) to today; -1 when unknown. */
    private fun daysSince(last: String, now: java.util.Calendar): Int = try {
        val f = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.ROOT)
        val a = f.parse(last)!!.time
        val today = f.parse(f.format(now.time))!!.time
        Math.round((today - a) / 86_400_000.0).toInt()
    } catch (_: Exception) {
        -1
    }

    /**
     * 1.39, the companion widget: the streak of days in a row with a record
     * (it lives while today or yesterday has one) and Finora's line about
     * it. Returns (mood, line, streak shown).
     */
    fun buddy(
        prefs: android.content.SharedPreferences,
        now: java.util.Calendar = java.util.Calendar.getInstance(),
    ): Triple<String, String, Int> {
        val (mood, line) = mood(prefs, now)
        val last = prefs.getString("lastEntry", "") ?: ""
        val streak = (prefs.getString("streak", "0") ?: "0").toIntOrNull() ?: 0
        val days = daysSince(last, now)
        val alive = if (days == 0 || days == 1) streak else 0
        val hour = now.get(java.util.Calendar.HOUR_OF_DAY)
        val text = when {
            mood == "angry" && prefs.getString("alertMood", "") == "angry" -> line
            mood == "sleep" -> line
            days == 0 && alive >= 2 && (prefs.getString("tileSay", "") ?: "").isEmpty() ->
                "Серия $alive ${daysWord(alive)}! Так держать 🔥"
            days == 0 && (prefs.getString("tileSay", "") ?: "").isNotEmpty() ->
                prefs.getString("tileSay", "") ?: ""
            days == 0 -> "Сегодня всё записано — умница!"
            days == 1 && alive >= 2 && hour >= 18 ->
                "Серия $alive ${daysWord(alive)} сгорит в полночь! Запишите хоть одну трату 😤"
            days == 1 && alive >= 2 -> "Не потеряйте серию: $alive ${daysWord(alive)}. Что сегодня потратили?"
            else -> line
        }
        return Triple(mood, text, alive)
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
        val (_, line) = mood(prefs)
        // 1.42: every widget shows Finora's picture of the moment on a
        // background of its colour.
        val name = pictureName(prefs)
        val picture = resource(name)
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
                val say = value("tileSay").ifEmpty { line }
                setTextViewText(R.id.widget_say, say)
                setOnClickPendingIntent(R.id.widget_root, FinoraBridge.launch(context, "open", 20 + id))
                setOnClickPendingIntent(R.id.widget_voice, FinoraBridge.launch(context, "voice", 30 + id))
                setOnClickPendingIntent(R.id.widget_add, FinoraBridge.launch(context, "expense", 40 + id))
                setOnClickPendingIntent(R.id.widget_scan, FinoraBridge.launch(context, "scan", 50 + id))
            }
            FinoraWidgetBuddy::class.java -> RemoteViews(context.packageName, R.layout.widget_buddy).apply {
                val (_, say, streak) = buddy(prefs)
                setTextViewText(R.id.widget_say, say)
                setTextViewText(
                    R.id.widget_streak,
                    if (streak > 0) "🔥 $streak ${daysWord(streak)} подряд" else "🔥 Начните серию",
                )
                setOnClickPendingIntent(R.id.widget_root, FinoraBridge.launch(context, "open", 70 + id))
                setOnClickPendingIntent(R.id.widget_say, FinoraBridge.launch(context, "voice", 80 + id))
                setOnClickPendingIntent(R.id.widget_add, FinoraBridge.launch(context, "expense", 90 + id))
            }
            FinoraWidgetSticker::class.java -> RemoteViews(context.packageName, R.layout.widget_sticker).apply {
                setOnClickPendingIntent(R.id.widget_root, FinoraBridge.launch(context, "expense", 100 + id))
            }
            FinoraWidgetMini::class.java -> RemoteViews(context.packageName, R.layout.widget_mini).apply {
                setOnClickPendingIntent(R.id.widget_root, FinoraBridge.launch(context, "expense", 110 + id))
            }
            else -> RemoteViews(context.packageName, R.layout.widget_payments).apply {
                setTextViewText(R.id.widget_title, value("paymentsTitle", "Ближайшие платежи"))
                setTextViewText(R.id.widget_payments, value("payments", "Платежей нет"))
                setOnClickPendingIntent(R.id.widget_root, FinoraBridge.launch(context, "payments", 60 + id))
            }
        }
        if (kind == FinoraWidgetPayments::class.java) {
            // The payments widget always talks about payments.
            val payName = when (value("payState")) {
                "overdue" -> "pay_dont_forget"
                "today" -> "payment_today"
                "" -> if (value("payments").startsWith("Финора спокойна")) "calm" else "payment_reminder"
                else -> "payment_reminder"
            }
            views.setImageViewResource(R.id.widget_finora, resource(payName))
            views.setInt(R.id.widget_root, "setBackgroundResource", background(payName))
        } else {
            views.setImageViewResource(R.id.widget_finora, picture)
            if (kind != FinoraWidgetSticker::class.java && kind != FinoraWidgetMini::class.java) {
                views.setInt(R.id.widget_root, "setBackgroundResource", background(name))
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

/** 1.39, 4×2: Finora as a companion — big, with a line and a streak. */
class FinoraWidgetBuddy : FinoraWidgetBase()

/** 1.40, 2×2: just Finora's picture for the moment; a tap — add an expense. */
class FinoraWidgetSticker : FinoraWidgetBase()

/** 1.42, 1×1: the smallest Finora — just her picture. */
class FinoraWidgetMini : FinoraWidgetBase()

/** 4×2: the next payments; Finora worries when one is due. */
class FinoraWidgetPayments : FinoraWidgetBase()
