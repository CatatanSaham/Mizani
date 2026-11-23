package com.mizani.money.domain.analytics

import com.mizani.money.core.model.Insight
import com.mizani.money.core.model.InsightKind
import com.mizani.money.core.model.InsightTone
import com.mizani.money.core.model.TransactionType
import com.mizani.money.core.money.Currency
import com.mizani.money.core.money.MoneyFormat
import com.mizani.money.core.time.DateRange
import com.mizani.money.core.time.Periods
import com.mizani.money.data.repo.LedgerSnapshot
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.ChronoUnit

/**
 * Deterministic, explainable rules. No generative AI, no opaque scoring. Every insight
 * states the values it was derived from and can be expanded to show the calculation.
 */
class InsightEngine(
    private val data: LedgerSnapshot,
    private val engine: AnalyticsEngine,
    private val currency: Currency,
) {

    private fun money(minor: Long): String = MoneyFormat.format(minor, currency)

    fun generate(metrics: DashboardMetrics, today: LocalDate = LocalDate.now()): List<Insight> {
        val insights = mutableListOf<Insight>()
        val period = metrics.period

        if (metrics.transactionCount == 0 && data.transactions.isEmpty()) {
            insights += Insight(
                id = "start",
                kind = InsightKind.DATA_COMPLETENESS,
                tone = InsightTone.NEUTRAL,
                title = "Mulai dengan satu transaksi nyata",
                body = "Catat uang yang benar-benar kamu terima atau keluarkan. Wawasan muncul setelah ada sedikit riwayat untuk dibandingkan.",
                explanation = "Catatan Keuangan tidak pernah memperkirakan pemasukan atau pengeluaranmu tanpa catatan. Tambahkan transaksi untuk mulai.",
                actionLabel = "Tambah transaksi",
            )
            return insights
        }

        val currentMonth = Periods.monthOf(today)
        val previousMonth = Periods.monthOf(today.minusMonths(1))
        val feeNow = engine.feesMinor(currentMonth)
        val feeBefore = engine.feesMinor(previousMonth)
        if (feeNow > 0 && feeBefore > 0 && feeNow > feeBefore * 1.15) {
            val increase = feeNow - feeBefore
            insights += Insight(
                id = "fees",
                kind = InsightKind.FEE_TREND,
                tone = InsightTone.ATTENTION,
                title = "Biaya lebih tinggi dari bulan lalu",
                body = "Kamu membayar ${money(feeNow)} biaya transaksi dan penarikan bulan ini, ${money(increase)} lebih banyak dari bulan lalu.",
                explanation = "Membandingkan biaya yang kamu catat bulan ini dengan bulan lalu. Biaya dicatat terpisah dari nominal transaksi.",
                actionLabel = "Lihat tren biaya",
            )
        }

        val incomeBySource = data.transactions
            .filter {
                it.type == TransactionType.INCOME && it.deletedAt == null &&
                    it.localDateEpochDay in currentMonth.start.toEpochDay()..currentMonth.end.toEpochDay()
            }
            .groupBy { it.incomeSourceId ?: it.categoryId ?: AnalyticsEngine.UNCATEGORISED }
            .mapValues { entry -> entry.value.sumOf { it.amountMinor } }
        val incomeTotal = incomeBySource.values.sum()
        if (incomeBySource.size >= 2 && incomeTotal > 0) {
            val top = incomeBySource.maxByOrNull { it.value }!!
            val share = top.value.toDouble() / incomeTotal
            if (share >= 0.7) {
                val label = data.incomeSourceName(top.key.takeIf { id ->
                    data.incomeSources.any { it.id == id }
                }) .let {
                    if (it == "Income") data.categoryName(top.key) else it
                }
                insights += Insight(
                    id = "income-concentration",
                    kind = InsightKind.INCOME_CONCENTRATION,
                    tone = InsightTone.NEUTRAL,
                    title = "Sebagian besar pemasukan bulan ini berasal dari satu sumber",
                    body = "${"%.0f".format(share * 100)}% pemasukan yang tercatat berasal dari $label.",
                    explanation = "Membandingkan pemasukan bulan ini per sumber. Ini menggambarkan aktivitas lalu dan tidak memprediksi pemasukan mendatang.",
                )
            }
        }

        val trend = spendingTrend(today)
        if (trend != null) {
            insights += trend
        }

        val lastTransaction = data.transactions
            .filter { it.deletedAt == null }
            .maxByOrNull { it.localDateEpochDay }
        if (lastTransaction != null && metrics.period.contains(today)) {
            val days = ChronoUnit.DAYS.between(LocalDate.ofEpochDay(lastTransaction.localDateEpochDay), today).toInt()
            if (days >= 7) {
                insights += Insight(
                    id = "quiet-week",
                    kind = InsightKind.DATA_COMPLETENESS,
                    tone = InsightTone.NEUTRAL,
                    title = "Tidak ada catatan selama $days hari",
                    body = "Analisis hanya mencerminkan apa yang kamu catat. Tambahkan aktivitas tunai atau dompet digital terbaru agar gambarannya tetap terkini.",
                    explanation = "Berdasarkan tanggal transaksi terakhir yang kamu catat. Catatan Keuangan tidak memperkirakan aktivitas yang hilang.",
                    actionLabel = "Tambah transaksi",
                )
            }
        }

        return insights
            .distinctBy { it.kind to it.id }
            .sortedWith(compareBy({ if (it.tone == InsightTone.ATTENTION) 0 else 1 }, { it.kind.ordinal }))
            .take(6)
    }

    private fun spendingTrend(today: LocalDate): Insight? {
        val current = Periods.monthOf(today)
        if (engine.transactionsIn(current).count { it.type == TransactionType.EXPENSE } < 3) return null
        val history = (1L..3L).map { back ->
            val month = YearMonth.from(today).minusMonths(back)
            val range = DateRange(month.atDay(1), month.atEndOfMonth())
            engine.categorySpendTotals(range)
        }
        if (history.any { it.isEmpty() }) return null
        val categories = engine.categorySpendTotals(current)
            .filterKeys { it != AnalyticsEngine.UNCATEGORISED }
            .mapValues { it.value }
        var best: Triple<String, Long, Long>? = null
        for ((categoryId, amount) in categories) {
            if (amount <= 0) continue
            val prior = history.mapNotNull { it[categoryId] }.filter { it > 0 }.sorted()
            if (prior.size < 3) continue
            val median = prior[1]
            if (median > 0 && amount > median * 1.25) {
                val currentBest = best
                if (currentBest == null || amount - median > currentBest.second - currentBest.third) {
                    best = Triple(categoryId, amount, median)
                }
            }
        }
        val found = best ?: return null
        val name = data.category(found.first)?.name ?: "Kategori"
        val delta = found.second - found.third
        return Insight(
            id = "trend-${found.first}",
            kind = InsightKind.SPENDING_TREND,
            tone = InsightTone.NEUTRAL,
            title = "$name di atas level bulanan biasamu",
            body = "Kamu sudah mengeluarkan ${money(found.second)} untuk $name bulan ini, sekitar ${money(delta)} lebih dari median terbaru ${money(found.third)}.",
            explanation = "Membandingkan pengeluaran bulan ini dengan bulan terbaru yang punya catatan pengeluaran di kategori ini.",
        )
    }
}
