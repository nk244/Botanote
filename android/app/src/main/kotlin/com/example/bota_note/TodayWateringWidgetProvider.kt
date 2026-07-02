package com.example.bota_note

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 今日の水やり予定をホーム画面に表示するウィジェット（Issue #174）。
/// 表示データは Flutter 側（HomeWidgetService）から書き込まれる。
class TodayWateringWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views =
          RemoteViews(context.packageName, R.layout.today_watering_widget).apply {
            val pendingIntent =
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            setOnClickPendingIntent(R.id.widget_container, pendingIntent)

            val count = widgetData.getInt("pendingWateringCount", 0)
            setTextViewText(R.id.widget_count, "${count}件")

            val summary =
                widgetData.getString("pendingWateringSummary", null)
                    ?: "今日の水やりはありません"
            setTextViewText(R.id.widget_summary, summary)
          }

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
