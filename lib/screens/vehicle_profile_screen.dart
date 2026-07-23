import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/vehicle_provider.dart';

class VehicleProfileScreen extends StatelessWidget {
  const VehicleProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => const _VehicleProfileBody();
}

class _VehicleProfileBody extends StatelessWidget {
  const _VehicleProfileBody();
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VehicleProvider>();
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Vehicle Profiles'),
        backgroundColor: AppColors.navyMid,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _showVehicleForm(context, provider, null),
          ),
        ],
      ),
      body: provider.vehicles.isEmpty
          ? _EmptyVehicles(onAdd: () => _showVehicleForm(context, provider, null))
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: provider.vehicles.length,
              itemBuilder: (_, i) {
                final v = provider.vehicles[i];
                final isActive = provider.active?.id == v.id;
                return _VehicleCard(
                  vehicle: v, isActive: isActive,
                  onSetActive: () => provider.setActive(v.id),
                  onEdit: () => _showVehicleForm(context, provider, v),
                  onDelete: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete Vehicle?'),
                        content: Text('Remove "${v.displayName}"?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) provider.deleteVehicle(v.id);
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showVehicleForm(context, provider, null),
        backgroundColor: AppColors.navyMid,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Vehicle', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  void _showVehicleForm(BuildContext ctx, VehicleProvider provider, VehicleProfile? existing) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VehicleForm(existing: existing, provider: provider),
    );
  }
}

// ── Vehicle Card ──────────────────────────────────────────────────────────────
class _VehicleCard extends StatelessWidget {
  final VehicleProfile vehicle;
  final bool isActive;
  final VoidCallback onSetActive, onEdit, onDelete;
  const _VehicleCard({required this.vehicle, required this.isActive,
      required this.onSetActive, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive ? AppColors.navyMid : AppColors.borderLight,
            width: isActive ? 2 : 1),
        boxShadow: [BoxShadow(color: AppColors.navyMid.withValues(alpha: 0.08),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: isActive ? AppColors.navyMid : AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.directions_car_rounded,
                  color: isActive ? Colors.white : AppColors.navyMid, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(vehicle.displayName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary))),
                if (isActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.navyMid,
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('ACTIVE', style: TextStyle(color: Colors.white,
                        fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ],
              ]),
              const SizedBox(height: 3),
              Text('${vehicle.year} · ${vehicle.fuelType.toUpperCase()} · '
                  '${vehicle.engineSizeL.toStringAsFixed(1)}L · ${vehicle.powerBhp} BHP',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ])),
          ]),
          if (vehicle.vin.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(color: AppColors.divider),
            Text('VIN: ${vehicle.vin}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary,
                    fontFamily: 'monospace')),
          ],
          const SizedBox(height: 14),
          Row(children: [
            if (!isActive) Expanded(child: OutlinedButton.icon(
              onPressed: onSetActive,
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Set Active'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.navyMid,
                  side: const BorderSide(color: AppColors.navyMid)),
            )),
            if (!isActive) const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.info,
                  side: const BorderSide(color: AppColors.info)),
            )),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onDelete,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: const Icon(Icons.delete_outline, size: 18),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _EmptyVehicles extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyVehicles({required this.onAdd});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.directions_car_outlined, size: 80, color: AppColors.textHint),
      const SizedBox(height: 16),
      const Text('No Vehicles Added', style: TextStyle(fontSize: 20,
          fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      const Text('Add your vehicle for personalised\nfuel and performance data.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.5)),
      const SizedBox(height: 24),
      ElevatedButton.icon(onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add First Vehicle'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.navyMid)),
    ]),
  );
}

// ── Vehicle Form ──────────────────────────────────────────────────────────────
class _VehicleForm extends StatefulWidget {
  final VehicleProfile? existing;
  final VehicleProvider provider;
  const _VehicleForm({this.existing, required this.provider});
  @override
  State<_VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends State<_VehicleForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _make, _model, _vin, _notes, _bhp, _weight;
  late int _year;
  late String _fuel;
  late double _engineSize;

  @override
  void initState() {
    super.initState();
    final v = widget.existing;
    _name       = TextEditingController(text: v?.name  ?? '');
    _make       = TextEditingController(text: v?.make  ?? '');
    _model      = TextEditingController(text: v?.model ?? '');
    _vin        = TextEditingController(text: v?.vin   ?? '');
    _notes      = TextEditingController(text: v?.notes ?? '');
    _bhp        = TextEditingController(text: (v?.powerBhp ?? 120).toString());
    _weight     = TextEditingController(text: (v?.weightKg ?? 1200).toStringAsFixed(0));
    _year       = v?.year        ?? DateTime.now().year;
    _fuel       = v?.fuelType    ?? 'petrol';
    _engineSize = v?.engineSizeL ?? 1.6;
  }

  @override
  void dispose() {
    for (final c in [_name,_make,_model,_vin,_notes,_bhp,_weight]) c.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final v = VehicleProfile(
      id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _name.text.trim(), make: _make.text.trim(), model: _model.text.trim(),
      year: _year, fuelType: _fuel, engineSizeL: _engineSize,
      powerBhp: int.tryParse(_bhp.text) ?? 120,
      weightKg: double.tryParse(_weight.text) ?? 1200,
      vin: _vin.text.trim(), notes: _notes.text.trim(),
    );
    if (widget.existing != null) widget.provider.updateVehicle(v);
    else widget.provider.addVehicle(v);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85, maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(color: AppColors.navyMid,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Row(children: [
              Text(widget.existing != null ? 'Edit Vehicle' : 'Add Vehicle',
                  style: const TextStyle(color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(onPressed: _save, child: const Text('SAVE',
                  style: TextStyle(color: AppColors.flameGold, fontWeight: FontWeight.w800))),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: ctrl,
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _FormField(ctrl: _name, label: 'Nickname', hint: 'e.g. My Swift',
                      validator: (v) => v!.isEmpty ? 'Required' : null),
                  _FormField(ctrl: _make, label: 'Make', hint: 'e.g. Maruti Suzuki'),
                  _FormField(ctrl: _model, label: 'Model', hint: 'e.g. Swift VXi'),
                  _DropField(label: 'Year', value: _year,
                    items: List.generate(35, (i) => DateTime.now().year - i),
                    display: (y) => '$y',
                    onChanged: (v) => setState(() => _year = v!)),
                  _DropField<String>(label: 'Fuel Type', value: _fuel,
                    items: ['petrol','diesel','hybrid','electric','cng','lpg'],
                    display: (f) => f[0].toUpperCase() + f.substring(1),
                    onChanged: (v) => setState(() => _fuel = v!)),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Engine Size', style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    Text('${_engineSize.toStringAsFixed(1)} L',
                        style: const TextStyle(fontWeight: FontWeight.w700,
                            color: AppColors.navyMid)),
                  ]),
                  Slider(value: _engineSize, min: 0.6, max: 8.0, divisions: 74,
                      activeColor: AppColors.navyMid,
                      onChanged: (v) => setState(() => _engineSize = v)),
                  _FormField(ctrl: _bhp, label: 'Power (BHP)',
                      hint: '120', keyboardType: TextInputType.number),
                  _FormField(ctrl: _weight, label: 'Weight (kg)',
                      hint: '1200', keyboardType: TextInputType.number),
                  _FormField(ctrl: _vin, label: 'VIN (optional)',
                      hint: '17-character vehicle identifier'),
                  _FormField(ctrl: _notes, label: 'Notes', hint: 'Any notes…', maxLines: 3),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 50,
                    child: ElevatedButton(onPressed: _save,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.navyMid),
                      child: Text(widget.existing != null ? 'Save Changes' : 'Add Vehicle',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
                  const SizedBox(height: 30),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final int maxLines;
  const _FormField({required this.ctrl, required this.label, required this.hint,
      this.validator, this.keyboardType = TextInputType.text, this.maxLines = 1});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      TextFormField(controller: ctrl, validator: validator,
          keyboardType: keyboardType, maxLines: maxLines,
          decoration: InputDecoration(hintText: hint)),
    ]),
  );
}

class _DropField<T> extends StatelessWidget {
  final String label; final T value; final List<T> items;
  final String Function(T) display; final ValueChanged<T?> onChanged;
  const _DropField({required this.label, required this.value,
      required this.items, required this.display, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      DropdownButtonFormField<T>(
        initialValue: value, decoration: const InputDecoration(),
        items: items.map((i) => DropdownMenuItem(value: i, child: Text(display(i)))).toList(),
        onChanged: onChanged),
    ]),
  );
}
