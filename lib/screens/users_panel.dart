import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/user.dart';
import '../state/user_provider.dart';
import '../widgets/bounded_content.dart';

/// Users admin panel — reached via Settings → Users. Lists staff accounts
/// (name, role) with add/edit/delete, backed by Supabase's staff_users
/// table via UserProvider. PINs are write-only from this screen's
/// perspective — never displayed or pre-filled, since only a hash is
/// ever stored.
class UsersPanel extends StatefulWidget {
  const UsersPanel({super.key});

  @override
  State<UsersPanel> createState() => _UsersPanelState();
}

class _UsersPanelState extends State<UsersPanel> {
  @override
  void initState() {
    super.initState();
    // Kick off the load after the first frame so context.read() during
    // build isn't an issue.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadFromSupabase();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserProvider>();
    final users = provider.users;

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(
        backgroundColor: AppColors.charcoal,
        elevation: 0,
        title: Text('Users', style: AppTextStyles.mono(size: 16, weight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.ledAmber,
        foregroundColor: AppColors.charcoal,
        onPressed: () => _showUserForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add user'),
      ),
      body: BoundedContent(
        child: provider.loading && users.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : provider.error != null && users.isEmpty
                ? Center(
                    child: Text(
                      provider.error!,
                      style: AppTextStyles.body(size: 14, color: AppColors.ledgerRed),
                    ),
                  )
                : users.isEmpty
                    ? Center(
                        child: Text(
                          'No users yet',
                          style: AppTextStyles.body(size: 14, color: AppColors.textSecondary),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => context.read<UserProvider>().loadFromSupabase(),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                          itemCount: users.length,
                          itemBuilder: (context, i) => _UserRow(user: users[i]),
                        ),
                      ),
      ),
    );
  }

  static void _showUserForm(BuildContext context, {AppUser? existing}) {
    showDialog(
      context: context,
      builder: (_) => _UserFormDialog(existing: existing),
    );
  }
}

class _UserRow extends StatelessWidget {
  final AppUser user;
  const _UserRow({required this.user});

  @override
  Widget build(BuildContext context) {
    final isAdmin = user.role == UserRole.admin;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slateBorder, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _UsersPanelState._showUserForm(context, existing: user),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.slateField,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.slateBorder, width: 1),
                ),
                child: Icon(
                  isAdmin ? Icons.shield_outlined : Icons.point_of_sale_outlined,
                  size: 18,
                  color: AppColors.ledAmber,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _RoleBadge(role: user.role),
                        const SizedBox(width: 8),
                        // No PIN length to reflect anymore -- only a
                        // hash exists server-side -- so this is just a
                        // fixed placeholder instead of '•' * pin.length.
                        Text(
                          '•  PIN ••••',
                          style: AppTextStyles.mono(size: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.textSecondary),
                tooltip: 'Edit',
                onPressed: () => _UsersPanelState._showUserForm(context, existing: user),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: AppColors.ledgerRed),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, user),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppUser user) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.slate,
        title: Text('Remove user?', style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
        content: Text(
          'Remove "${user.name}" from the account list? This can\'t be undone.',
          style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: AppTextStyles.body(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final provider = context.read<UserProvider>();
              Navigator.of(dialogContext).pop();
              try {
                await provider.deleteUser(user.id);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not remove user. Please try again.')),
                  );
                }
              }
            },
            child: Text('Remove', style: AppTextStyles.body(color: AppColors.ledgerRed, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final UserRole role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == UserRole.admin;
    final color = isAdmin ? AppColors.ledAmber : AppColors.tillGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Text(
        role.label.toUpperCase(),
        style: AppTextStyles.mono(size: 10, weight: FontWeight.w700, color: color, letterSpacing: 1),
      ),
    );
  }
}

/// Add/edit form. Reused for both — `existing` null means "add new".
/// On edit, the PIN field starts empty and stays optional: leaving it
/// blank keeps the existing PIN, since a plaintext PIN is never
/// available to pre-fill from Supabase (only pin_hash is stored).
class _UserFormDialog extends StatefulWidget {
  final AppUser? existing;
  const _UserFormDialog({this.existing});

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _pinController;
  late UserRole _role;
  String? _error;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _pinController = TextEditingController(); // always starts blank now
    _role = widget.existing?.role ?? UserRole.cashier;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final pin = _pinController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    // On add, a PIN is mandatory. On edit, blank means "keep current."
    if (!_isEditing && pin.isEmpty) {
      setState(() => _error = 'PIN is required.');
      return;
    }
    if (pin.isNotEmpty && (pin.length < 4 || pin.length > 6)) {
      setState(() => _error = 'PIN must be 4–6 digits.');
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    final provider = context.read<UserProvider>();
    try {
      if (_isEditing) {
        await provider.updateUser(widget.existing!.id, name: name, role: _role, pin: pin);
      } else {
        await provider.addUser(name: name, role: _role, pin: pin);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong saving this user. Please try again.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.slate,
      title: Text(
        _isEditing ? 'Edit user' : 'Add user',
        style: AppTextStyles.body(size: 16, weight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              style: AppTextStyles.body(size: 14),
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 16),
            Text(
              'ROLE',
              style: AppTextStyles.mono(size: 11, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _RoleChip(role: UserRole.cashier, selected: _role == UserRole.cashier, onTap: () => setState(() => _role = UserRole.cashier))),
                const SizedBox(width: 8),
                Expanded(child: _RoleChip(role: UserRole.admin, selected: _role == UserRole.admin, onTap: () => setState(() => _role = UserRole.admin))),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              style: AppTextStyles.mono(size: 14),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                labelText: _isEditing ? 'New PIN (leave blank to keep current)' : 'PIN (4–6 digits)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppTextStyles.body(size: 12, color: AppColors.ledgerRed)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: AppTextStyles.body(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  height: 16, width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _isEditing ? 'Save' : 'Add',
                  style: AppTextStyles.body(color: AppColors.ledAmber, weight: FontWeight.w700),
                ),
        ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({required this.role, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.ledAmber.withOpacity(0.15) : AppColors.slateField,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.ledAmber : AppColors.slateBorder,
            width: 1,
          ),
        ),
        child: Text(
          role.label,
          style: AppTextStyles.body(
            size: 13,
            weight: FontWeight.w600,
            color: selected ? AppColors.ledAmber : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
