import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_db.dart';
import 'fintech_design.dart';
import 'models.dart';

final _cardMoney = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

class CardsPage extends StatefulWidget {
  final VoidCallback onChanged;
  const CardsPage({super.key, required this.onChanged});

  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  String period = 'month';
  int year = DateTime.now().year;
  int month = DateTime.now().month;

  (int, int) get _range => period == 'year'
      ? (DateTime(year, 1, 1).millisecondsSinceEpoch, DateTime(year + 1, 1, 1).millisecondsSinceEpoch)
      : (DateTime(year, month, 1).millisecondsSinceEpoch, DateTime(year, month + 1, 1).millisecondsSinceEpoch);

  Future<List<dynamic>> _load() async {
    await AppDb.instance.autoLinkCardTransactions();
    final cards = await AppDb.instance.paymentCards();
    final range = _range;
    return Future.wait<dynamic>([
      Future.value(cards),
      Future.wait(cards.map((card) => AppDb.instance.cardTotals(card.id!))),
      Future.wait(cards.map((card) => AppDb.instance.cardTotals(card.id!, startMs: range.$1, endMs: range.$2))),
    ]);
  }

  Future<void> _addCard() async {
    final name = TextEditingController();
    final issuer = TextEditingController();
    final lastFour = TextEditingController();
    final limit = TextEditingController();
    String type = 'credit';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add a card'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Card name', hintText: 'HDFC Millennia')),
          const SizedBox(height: 10),
          TextField(controller: issuer, decoration: const InputDecoration(labelText: 'Bank / issuer')),
          const SizedBox(height: 10),
          TextField(controller: lastFour, maxLength: 4, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Last 4 digits', hintText: '1234')),
          const SizedBox(height: 4),
          SegmentedButton<String>(segments: const [ButtonSegment(value: 'credit', label: Text('Credit')), ButtonSegment(value: 'debit', label: Text('Debit'))], selected: {type}, onSelectionChanged: (value) => setDialogState(() => type = value.first)),
          if (type == 'credit') ...[const SizedBox(height: 10), TextField(controller: limit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Credit limit', prefixText: '₹ '))],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add card')),
        ],
      )),
    );
    if (saved == true && name.text.trim().isNotEmpty) {
      await AppDb.instance.addPaymentCard(name: name.text, issuer: issuer.text, lastFour: lastFour.text, cardType: type, creditLimit: double.tryParse(limit.text.replaceAll(',', '')) ?? 0);
      if (mounted) { setState(() {}); widget.onChanged(); }
    }
    name.dispose(); issuer.dispose(); lastFour.dispose(); limit.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: _load(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Could not load cards: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final cards = snap.data![0] as List<PaymentCardRecord>;
      final allTotals = snap.data![1] as List<Map<String, double>>;
      final selectedTotals = snap.data![2] as List<Map<String, double>>;
      return ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 104), children: [
        Row(children: [const Expanded(child: _CardsHeader()), IconButton.filledTonal(onPressed: _addCard, icon: const Icon(Icons.add_rounded))]),
        const SizedBox(height: 16),
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'month', label: Text('Month')), ButtonSegment(value: 'year', label: Text('Year'))], selected: {period}, onSelectionChanged: (value) => setState(() => period = value.first)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: DropdownButtonFormField<int>(value: year, decoration: const InputDecoration(labelText: 'Year'), items: List.generate(6, (i) { final value = DateTime.now().year - i; return DropdownMenuItem(value: value, child: Text('$value')); }), onChanged: (value) { if (value != null) setState(() => year = value); })),
          if (period == 'month') ...[const SizedBox(width: 10), Expanded(child: DropdownButtonFormField<int>(value: month, decoration: const InputDecoration(labelText: 'Month'), items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(DateFormat.MMMM().format(DateTime(2024, i + 1))))), onChanged: (value) { if (value != null) setState(() => month = value); }))],
        ]),
        const SizedBox(height: 22),
        if (cards.isEmpty) FintechSurface(child: Column(children: [const Icon(Icons.credit_card_rounded, size: 38), const SizedBox(height: 12), const Text('Add your debit or credit card', style: TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 5), const Text('Use the last four digits so matching card SMS can be linked automatically.'), const SizedBox(height: 12), OutlinedButton.icon(onPressed: _addCard, icon: const Icon(Icons.add), label: const Text('Add card'))]))
        else ...List.generate(cards.length, (index) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _CardOverview(card: cards[index], allTotals: allTotals[index], periodTotals: selectedTotals[index], onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => CardDetailsPage(card: cards[index]))); if (mounted) setState(() {}); widget.onChanged(); }))),
      ]);
    },
  );
}

class _CardsHeader extends StatelessWidget {
  const _CardsHeader();
  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Cards', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)), SizedBox(height: 4), Text('Utilisation, bill payments and card-wise spending')]);
}

class _CardOverview extends StatelessWidget {
  final PaymentCardRecord card; final Map<String, double> allTotals; final Map<String, double> periodTotals; final VoidCallback onTap;
  const _CardOverview({required this.card, required this.allTotals, required this.periodTotals, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final purchases = allTotals['purchase'] ?? 0; final payments = allTotals['payment'] ?? 0;
    final outstanding = (purchases - payments).clamp(0, double.infinity).toDouble();
    final periodSpent = periodTotals['purchase'] ?? 0;
    final ratio = card.cardType == 'credit' && card.creditLimit > 0 ? (outstanding / card.creditLimit).clamp(0.0, 1.0).toDouble() : 0.0;
    return FintechSurface(onTap: onTap, tint: card.cardType == 'credit' ? const Color(0xFFF1F7F3) : const Color(0xFFF4F4FB), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .75), borderRadius: BorderRadius.circular(13)), child: Icon(card.cardType == 'credit' ? Icons.credit_card_rounded : Icons.account_balance_wallet_rounded)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(card.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), Text('${card.issuer.isEmpty ? 'Card' : card.issuer} •••• ${card.lastFour.isEmpty ? '—' : card.lastFour}')]))]),
      const SizedBox(height: 16),
      Row(children: [Expanded(child: _CardMetric(label: card.cardType == 'credit' ? 'Outstanding' : 'Spent in period', value: _cardMoney.format(card.cardType == 'credit' ? outstanding : periodSpent))), Expanded(child: _CardMetric(label: card.cardType == 'credit' ? 'Credit limit' : 'Card type', value: card.cardType == 'credit' ? _cardMoney.format(card.creditLimit) : 'Debit'))]),
      if (card.cardType == 'credit' && card.creditLimit > 0) ...[const SizedBox(height: 12), LinearProgressIndicator(value: ratio, minHeight: 7, borderRadius: BorderRadius.circular(9)), const SizedBox(height: 5), Text('${(ratio * 100).round()}% utilised', style: Theme.of(context).textTheme.bodySmall)],
    ]));
  }
}

class _CardMetric extends StatelessWidget { final String label; final String value; const _CardMetric({required this.label, required this.value}); @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 3), Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))]); }

class CardDetailsPage extends StatefulWidget { final PaymentCardRecord card; const CardDetailsPage({super.key, required this.card}); @override State<CardDetailsPage> createState() => _CardDetailsPageState(); }
class _CardDetailsPageState extends State<CardDetailsPage> {
  String period = 'month'; int year = DateTime.now().year; int month = DateTime.now().month;
  (int, int) get _range => period == 'year' ? (DateTime(year, 1, 1).millisecondsSinceEpoch, DateTime(year + 1, 1, 1).millisecondsSinceEpoch) : (DateTime(year, month, 1).millisecondsSinceEpoch, DateTime(year, month + 1, 1).millisecondsSinceEpoch);
  Future<List<dynamic>> _load() async {
    final range = _range;
    return Future.wait<dynamic>([
      AppDb.instance.cardTotals(widget.card.id!),
      AppDb.instance.cardLedger(widget.card.id!, startMs: range.$1, endMs: range.$2),
      AppDb.instance.cardSpendByCategory(widget.card.id!, startMs: range.$1, endMs: range.$2),
      AppDb.instance.cardSpendByMerchant(widget.card.id!, startMs: range.$1, endMs: range.$2),
      AppDb.instance.cardMonthlySpend(widget.card.id!, year),
    ]);
  }
  Future<void> _markOutstandingPaid() async {
    final totals = await AppDb.instance.cardTotals(widget.card.id!);
    final amount = ((totals['purchase'] ?? 0) - (totals['payment'] ?? 0)).clamp(0, double.infinity).toDouble();
    if (amount <= 0) return;
    await AppDb.instance.markCardBillPaid(cardId: widget.card.id!, amount: amount, occurredAt: DateTime.now().millisecondsSinceEpoch);
    if (mounted) setState(() {});
  }
  Future<void> _record(String type) async { final amount = TextEditingController(); final merchant = TextEditingController(); final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(type == 'payment' ? 'Mark card bill paid' : 'Add card transaction'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ')), if (type == 'purchase') ...[const SizedBox(height: 10), TextField(controller: merchant, decoration: const InputDecoration(labelText: 'Merchant'))]]), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))])); if (ok == true) { final value = double.tryParse(amount.text.replaceAll(',', '')); if (value != null && value > 0) { await AppDb.instance.addCardLedgerEntry(cardId: widget.card.id!, entryType: type, amount: value, occurredAt: DateTime.now().millisecondsSinceEpoch, merchant: type == 'payment' ? 'Credit card bill payment' : merchant.text); if (mounted) setState(() {}); } } amount.dispose(); merchant.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.card.name), actions: [IconButton(onPressed: _markOutstandingPaid, icon: const Icon(Icons.payments_outlined), tooltip: 'Mark bill paid')]), body: FutureBuilder<List<dynamic>>(future: _load(), builder: (context, snap) { if (!snap.hasData) return const Center(child: CircularProgressIndicator()); final totals = snap.data![0] as Map<String, double>; final entries = snap.data![1] as List<CardLedgerEntry>; final categories = snap.data![2] as List<Map<String, Object?>>; final merchants = snap.data![3] as List<Map<String, Object?>>; final months = snap.data![4] as List<Map<String, Object?>>; final outstanding = ((totals['purchase'] ?? 0) - (totals['payment'] ?? 0)).clamp(0, double.infinity).toDouble(); final periodSpend = categories.fold<double>(0, (sum, row) => sum + ((row['total'] as num?) ?? 0).toDouble()); final utilisation = widget.card.creditLimit <= 0 ? 0.0 : (outstanding / widget.card.creditLimit).clamp(0.0, 1.0).toDouble(); return ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 32), children: [_CardReportHero(card: widget.card, outstanding: outstanding, utilisation: utilisation, onPaid: _markOutstandingPaid), const SizedBox(height: 18), SegmentedButton<String>(segments: const [ButtonSegment(value: 'month', label: Text('Month')), ButtonSegment(value: 'year', label: Text('Year'))], selected: {period}, onSelectionChanged: (value) => setState(() => period = value.first)), const SizedBox(height: 14), Row(children: [Expanded(child: DropdownButtonFormField<int>(value: year, decoration: const InputDecoration(labelText: 'Year'), items: List.generate(6, (i) { final y = DateTime.now().year - i; return DropdownMenuItem(value: y, child: Text('$y')); }), onChanged: (v) { if (v != null) setState(() => year = v); })), if (period == 'month') ...[const SizedBox(width: 10), Expanded(child: DropdownButtonFormField<int>(value: month, decoration: const InputDecoration(labelText: 'Month'), items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(DateFormat.MMM().format(DateTime(2024, i + 1))))), onChanged: (v) { if (v != null) setState(() => month = v); }))]]), const SizedBox(height: 22), Text('Spending report', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), Text('${period == 'month' ? DateFormat.MMMM().format(DateTime(year, month)) : year} • ${_cardMoney.format(periodSpend)} spent', style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: 10), _InsightBars(title: 'Where your money went', rows: categories, emptyText: 'No purchase data for this period.'), const SizedBox(height: 12), _InsightBars(title: 'Top merchants', rows: merchants, emptyText: 'No merchant data for this period.'), const SizedBox(height: 12), _MonthBars(year: year, rows: months), const SizedBox(height: 20), Row(children: [const Expanded(child: Text('Card transactions', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18))), TextButton.icon(onPressed: () => _record('purchase'), icon: const Icon(Icons.add), label: const Text('Add'))]), if (entries.isEmpty) const Padding(padding: EdgeInsets.only(top: 16), child: Text('No mapped card transactions for this period. Add one manually or include the card last four digits to auto-link matching SMS.')) else ...entries.map((entry) => ListTile(leading: CircleAvatar(child: Icon(entry.entryType == 'payment' ? Icons.payments_rounded : Icons.shopping_bag_outlined)), title: Text(entry.merchant.isEmpty ? (entry.entryType == 'payment' ? 'Card bill payment' : 'Card transaction') : entry.merchant), subtitle: Text(DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(entry.occurredAt))), trailing: Text('${entry.entryType == 'payment' ? '-' : '+'}${_cardMoney.format(entry.amount)}', style: TextStyle(fontWeight: FontWeight.w900, color: entry.entryType == 'payment' ? const Color(0xFF0A8B56) : Theme.of(context).colorScheme.onSurface)))), ]); }));
}

class _CardReportHero extends StatelessWidget {
  final PaymentCardRecord card; final double outstanding; final double utilisation; final VoidCallback onPaid;
  const _CardReportHero({required this.card, required this.outstanding, required this.utilisation, required this.onPaid});
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF064B44), Color(0xFF089667), Color(0xFF39C584)]), borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: Color(0x26006443), blurRadius: 24, offset: Offset(0, 10))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(card.issuer.isEmpty ? 'CREDIT CARD' : card.issuer.toUpperCase(), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(card.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('••••  ••••  ••••  ${card.lastFour.isEmpty ? '—' : card.lastFour}', style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 1.5)), const SizedBox(height: 22), Row(children: [Expanded(child: _HeroMetric(label: 'Credit limit', value: _cardMoney.format(card.creditLimit))), Expanded(child: _HeroMetric(label: 'Outstanding', value: _cardMoney.format(outstanding))), Expanded(child: _HeroMetric(label: 'Utilisation', value: '${(utilisation * 100).round()}%'))]), const SizedBox(height: 12), LinearProgressIndicator(value: utilisation, minHeight: 8, borderRadius: BorderRadius.circular(9), color: const Color(0xFF8EFA64), backgroundColor: Colors.white30), const SizedBox(height: 14), Align(alignment: Alignment.centerRight, child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF087A57)), onPressed: onPaid, icon: const Icon(Icons.check_circle_outline), label: const Text('Mark bill paid')))]));
}
class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;
  const _HeroMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
          ),
        ],
      );
}

class _InsightBars extends StatelessWidget {
  final String title; final List<Map<String, Object?>> rows; final String emptyText;
  const _InsightBars({required this.title, required this.rows, required this.emptyText});
  @override Widget build(BuildContext context) { final max = rows.fold<double>(0, (v, row) => ((row['total'] as num?) ?? 0).toDouble() > v ? ((row['total'] as num?) ?? 0).toDouble() : v); return FintechSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), if (rows.isEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(emptyText)) else ...rows.map((row) { final value = ((row['total'] as num?) ?? 0).toDouble(); return Padding(padding: const EdgeInsets.only(top: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text('${row['label']}', overflow: TextOverflow.ellipsis)), Text(_cardMoney.format(value), style: const TextStyle(fontWeight: FontWeight.w800))]), const SizedBox(height: 5), LinearProgressIndicator(value: max == 0 ? 0 : value / max, minHeight: 7, borderRadius: BorderRadius.circular(9))])); })])); }
}

class _MonthBars extends StatelessWidget {
  final int year; final List<Map<String, Object?>> rows; const _MonthBars({required this.year, required this.rows});
  @override Widget build(BuildContext context) { final max = rows.fold<double>(0, (v, row) => ((row['total'] as num?) ?? 0).toDouble() > v ? ((row['total'] as num?) ?? 0).toDouble() : v); return FintechSurface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$year monthly spending', style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 14), SizedBox(height: 112, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: rows.map((row) { final value = ((row['total'] as num?) ?? 0).toDouble(); final height = max == 0 ? 4.0 : 4 + 58 * value / max; return Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [Text(value == 0 ? '' : '${(value / 1000).toStringAsFixed(0)}k', style: const TextStyle(fontSize: 9)), Container(height: height, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: const Color(0xFF11845B), borderRadius: BorderRadius.circular(5))), const SizedBox(height: 4), Text('${row['label']}', style: const TextStyle(fontSize: 8))])); }).toList()))])); }
}
