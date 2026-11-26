package com.drago.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

/**
 * Widget de calendario en la pantalla de inicio.
 *
 * La app (Dart, WidgetService) guarda en "calendar" los movimientos pendientes
 * de los próximos meses y los colores del tema. Aquí solo se dibujan:
 * - chico (poca altura): próximos movimientos;
 * - grande: mes completo con puntos de color + próximos movimientos.
 * Las flechas cambian de mes (hasta 3 meses adelante) y tocar un día o un
 * movimiento abre Drago en ese lugar.
 */
class DragoCalendarWidget : HomeWidgetProvider() {

    companion object {
        private const val ACTION_PREV = "com.drago.app.widget.PREV"
        private const val ACTION_NEXT = "com.drago.app.widget.NEXT"
        private const val STATE = "drago_widget_state"
        private const val MAX_OFFSET = 3
        private val MONTHS = arrayOf(
            "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
            "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"
        )
        private val SHORT = arrayOf("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")
    }

    private class Ev(val date: String, val title: String, val amount: String, val income: Boolean, val overdue: Boolean, val uri: String)

    private class Colors(json: JSONObject?) {
        val bg = json?.optInt("bg", 0xFFF4FBF8.toInt()) ?: 0xFFF4FBF8.toInt()
        val text = json?.optInt("text", 0xFF1B1B1B.toInt()) ?: 0xFF1B1B1B.toInt()
        val muted = json?.optInt("muted", 0xFF5F6B66.toInt()) ?: 0xFF5F6B66.toInt()
        val primary = json?.optInt("primary", 0xFF1F6F5C.toInt()) ?: 0xFF1F6F5C.toInt()
        val onPrimary = json?.optInt("onPrimary", 0xFFFFFFFF.toInt()) ?: 0xFFFFFFFF.toInt()
        val income = json?.optInt("income", 0xFF1B8A5A.toInt()) ?: 0xFF1B8A5A.toInt()
        val expense = json?.optInt("expense", 0xFFC0392B.toInt()) ?: 0xFFC0392B.toInt()
        val pending = json?.optInt("pending", 0xFFB26A00.toInt()) ?: 0xFFB26A00.toInt()
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) render(context, appWidgetManager, id, widgetData)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == ACTION_PREV || action == ACTION_NEXT) {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return
            val state = context.getSharedPreferences(STATE, Context.MODE_PRIVATE)
            val current = state.getInt("offset_$id", 0)
            val next = (current + if (action == ACTION_NEXT) 1 else -1).coerceIn(0, MAX_OFFSET)
            state.edit().putInt("offset_$id", next).apply()
            render(context, AppWidgetManager.getInstance(context), id, HomeWidgetPlugin.getData(context))
            return
        }
        super.onReceive(context, intent)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val edit = context.getSharedPreferences(STATE, Context.MODE_PRIVATE).edit()
        for (id in appWidgetIds) edit.remove("offset_$id")
        edit.apply()
    }

    private fun ymd(c: Calendar): String =
        String.format(Locale.US, "%04d-%02d-%02d", c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))

    private fun launch(context: Context, uri: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(uri))

    private fun arrow(context: Context, id: Int, action: String): PendingIntent {
        val intent = Intent(context, DragoCalendarWidget::class.java)
            .setAction(action)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
        val code = id * 2 + if (action == ACTION_NEXT) 1 else 0
        return PendingIntent.getBroadcast(context, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun render(context: Context, manager: AppWidgetManager, id: Int, data: SharedPreferences) {
        val pkg = context.packageName
        val json = try {
            data.getString("calendar", null)?.let { JSONObject(it) }
        } catch (e: Exception) {
            null
        }
        val colors = Colors(json?.optJSONObject("colors"))
        val hide = json?.optBoolean("hide", false) ?: false
        val events = mutableListOf<Ev>()
        json?.optJSONArray("events")?.let { arr ->
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                events.add(
                    Ev(
                        o.optString("d"), o.optString("t"), o.optString("a"),
                        o.optString("k") == "i", o.optInt("o", 0) == 1, o.optString("u", "drago://calendar")
                    )
                )
            }
        }

        // Tamaño: en vertical la altura real es la máxima que reporta el sistema.
        val options = manager.getAppWidgetOptions(id)
        val minH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
        val maxH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, minH)
        val height = if (maxH > 0) maxH else minH
        val large = height >= 230

        val today = Calendar.getInstance()
        val todayKey = ymd(today)
        val offset = if (large) context.getSharedPreferences(STATE, Context.MODE_PRIVATE).getInt("offset_$id", 0) else 0
        val month = Calendar.getInstance().apply {
            set(Calendar.DAY_OF_MONTH, 1)
            add(Calendar.MONTH, offset)
        }

        val views = RemoteViews(pkg, R.layout.widget_calendar)
        views.setInt(R.id.bg, "setColorFilter", colors.bg)
        views.setTextColor(R.id.title, colors.text)
        views.setTextColor(R.id.prev, if (offset > 0) colors.primary else colors.muted and 0x55FFFFFF)
        views.setTextColor(R.id.next, if (offset < MAX_OFFSET) colors.primary else colors.muted and 0x55FFFFFF)
        views.setTextColor(R.id.list_label, colors.muted)
        views.setTextColor(R.id.empty, colors.muted)
        for (wd in intArrayOf(R.id.wd0, R.id.wd1, R.id.wd2, R.id.wd3, R.id.wd4, R.id.wd5, R.id.wd6)) {
            views.setTextColor(wd, colors.muted)
        }

        val monthName = "${MONTHS[month.get(Calendar.MONTH)]} ${month.get(Calendar.YEAR)}"
        val monthUri = "drago://calendar?date=${if (offset == 0) todayKey else ymd(month)}"
        views.setOnClickPendingIntent(R.id.title, launch(context, monthUri))

        if (large) {
            views.setTextViewText(R.id.title, monthName)
            views.setViewVisibility(R.id.prev, View.VISIBLE)
            views.setViewVisibility(R.id.next, View.VISIBLE)
            views.setOnClickPendingIntent(R.id.prev, arrow(context, id, ACTION_PREV))
            views.setOnClickPendingIntent(R.id.next, arrow(context, id, ACTION_NEXT))
            views.setViewVisibility(R.id.weekdays, View.VISIBLE)
            views.setViewVisibility(R.id.grid, View.VISIBLE)
        } else {
            views.setTextViewText(R.id.title, if (json == null) "Drago" else "Próximos · $monthName")
            views.setViewVisibility(R.id.prev, View.GONE)
            views.setViewVisibility(R.id.next, View.GONE)
            views.setViewVisibility(R.id.weekdays, View.GONE)
            views.setViewVisibility(R.id.grid, View.GONE)
        }

        // Lista: en el mes actual, los próximos (vencidos primero); al ver otro
        // mes, los movimientos de ese mes.
        val monthKey = ymd(month).substring(0, 7)
        val candidates = if (offset == 0) events.filter { it.overdue || it.date >= todayKey }
        else events.filter { it.date.startsWith(monthKey) }
        val weeks = weeksIn(month)
        val rows: Int
        if (large) {
            // Alto disponible bajo los días de la semana. Si sobra espacio
            // después de la lista, las semanas se hacen más altas.
            val avail = height - 20 - 28 - 16 - 24
            val tall = avail - weeks * 44 >= minOf(candidates.size, 4) * 22
            renderGrid(context, views, month, todayKey, events, colors, tall)
            rows = ((avail - weeks * (if (tall) 44 else 32)) / 22).coerceIn(0, 15)
            views.setTextViewText(R.id.list_label, if (offset == 0) "Próximos" else "En ${MONTHS[month.get(Calendar.MONTH)].lowercase()}")
        } else {
            rows = ((height - 20 - 28) / 22).coerceIn(1, 15)
        }
        val upcoming = candidates.take(rows)
        views.removeAllViews(R.id.list)
        views.setViewVisibility(R.id.list_label, if (large && rows > 0) View.VISIBLE else View.GONE)
        if (json == null) {
            views.setViewVisibility(R.id.empty, View.VISIBLE)
            views.setTextViewText(R.id.empty, "Abre Drago para cargar tu calendario.")
        } else {
            views.setViewVisibility(R.id.empty, if (upcoming.isEmpty() && rows > 0) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.empty, if (offset == 0) "Sin pagos próximos." else "Sin movimientos este mes.")
        }
        for (e in upcoming) {
            val row = RemoteViews(pkg, R.layout.widget_event_row)
            row.setTextViewText(R.id.date, if (e.overdue && e.date < todayKey) "Vencido" else shortDate(e.date, todayKey))
            row.setTextColor(R.id.date, if (e.overdue) colors.expense else colors.muted)
            row.setTextViewText(R.id.name, e.title)
            row.setTextColor(R.id.name, colors.text)
            row.setTextViewText(R.id.amount, if (hide) "" else e.amount)
            row.setTextColor(R.id.amount, if (e.income) colors.income else if (e.overdue) colors.expense else colors.text)
            row.setOnClickPendingIntent(R.id.event, launch(context, e.uri))
            views.addView(R.id.list, row)
        }

        manager.updateAppWidget(id, views)
    }

    private fun weeksIn(month: Calendar): Int {
        val first = month.clone() as Calendar
        first.set(Calendar.DAY_OF_MONTH, 1)
        val lead = (first.get(Calendar.DAY_OF_WEEK) + 5) % 7
        val days = first.getActualMaximum(Calendar.DAY_OF_MONTH)
        return (lead + days + 6) / 7
    }

    private fun shortDate(date: String, todayKey: String): String {
        if (date == todayKey) return "Hoy"
        val parts = date.split("-")
        if (parts.size != 3) return date
        val m = parts[1].toIntOrNull() ?: return date
        val d = parts[2].toIntOrNull() ?: return date
        return "$d ${SHORT[(m - 1).coerceIn(0, 11)]}"
    }

    private fun renderGrid(context: Context, views: RemoteViews, month: Calendar, todayKey: String, events: List<Ev>, colors: Colors, tall: Boolean) {
        val pkg = context.packageName
        // Qué hay cada día: ingreso, pago pendiente o pago vencido.
        val income = HashSet<String>()
        val pending = HashSet<String>()
        val overdue = HashSet<String>()
        for (e in events) {
            when {
                e.income -> income.add(e.date)
                e.overdue -> overdue.add(e.date)
                else -> pending.add(e.date)
            }
        }
        views.removeAllViews(R.id.grid)
        val first = month.clone() as Calendar
        first.set(Calendar.DAY_OF_MONTH, 1)
        val lead = (first.get(Calendar.DAY_OF_WEEK) + 5) % 7 // lunes = 0
        val days = first.getActualMaximum(Calendar.DAY_OF_MONTH)
        val weeks = weeksIn(month)
        val day = first.clone() as Calendar
        for (w in 0 until weeks) {
            val row = RemoteViews(pkg, if (tall) R.layout.widget_week_row_tall else R.layout.widget_week_row)
            for (c in 0 until 7) {
                val cell = RemoteViews(pkg, R.layout.widget_day)
                val n = w * 7 + c - lead + 1
                if (n in 1..days) {
                    day.set(Calendar.DAY_OF_MONTH, n)
                    val key = ymd(day)
                    cell.setTextViewText(R.id.day, n.toString())
                    if (key == todayKey) {
                        cell.setTextColor(R.id.day, colors.onPrimary)
                        cell.setInt(R.id.day, "setBackgroundResource", R.drawable.widget_today)
                        if (Build.VERSION.SDK_INT >= 31) {
                            cell.setColorStateList(R.id.day, "setBackgroundTintList", ColorStateList.valueOf(colors.primary))
                        } else {
                            cell.setInt(R.id.day, "setBackgroundColor", colors.primary)
                        }
                    } else {
                        cell.setTextColor(R.id.day, colors.text)
                    }
                    if (income.contains(key)) {
                        cell.setViewVisibility(R.id.dot_i, View.VISIBLE)
                        cell.setInt(R.id.dot_i, "setColorFilter", colors.income)
                    }
                    if (pending.contains(key) || overdue.contains(key)) {
                        cell.setViewVisibility(R.id.dot_e, View.VISIBLE)
                        cell.setInt(R.id.dot_e, "setColorFilter", if (overdue.contains(key)) colors.expense else colors.pending)
                    }
                    cell.setOnClickPendingIntent(R.id.cell, launch(context, "drago://calendar?date=$key"))
                } else {
                    cell.setTextViewText(R.id.day, "")
                }
                row.addView(R.id.row, cell)
            }
            views.addView(R.id.grid, row)
        }
    }
}
