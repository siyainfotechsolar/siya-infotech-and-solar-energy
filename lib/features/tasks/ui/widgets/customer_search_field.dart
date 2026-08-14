import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/providers/auth_provider.dart';

class CustomerSearchField extends ConsumerStatefulWidget {
  final String? initialCustomerId;
  final ValueChanged<String?> onCustomerSelected;

  const CustomerSearchField({
    super.key,
    this.initialCustomerId,
    required this.onCustomerSelected,
  });

  @override
  ConsumerState<CustomerSearchField> createState() => _CustomerSearchFieldState();
}

class _CustomerSearchFieldState extends ConsumerState<CustomerSearchField> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  
  Timer? _debounce;
  bool _isLoading = false;
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selectedCustomer;
  
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        // Delay hiding to allow tap to register
        Future.delayed(const Duration(milliseconds: 200), _hideOverlay);
      }
    });

    if (widget.initialCustomerId != null) {
      _loadInitialCustomer();
    }
  }

  Future<void> _loadInitialCustomer() async {
    try {
      final supabase = ref.read(supabaseClientProvider);
      final res = await supabase.from('customers').select('id, name, customer_id, mobile, consumer_number, village').eq('id', widget.initialCustomerId!).single();
      setState(() {
        _selectedCustomer = res;
        _searchController.text = res['name'];
      });
      widget.onCustomerSelected(res['id']);
    } catch (e) {
      // Ignored
    }
  }

  void _onSearchChanged() {
    if (_selectedCustomer != null && _searchController.text != _selectedCustomer!['name']) {
      // User typed something else after selecting a customer
      setState(() {
        _selectedCustomer = null;
      });
      widget.onCustomerSelected(null);
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() {
        _results = [];
      });
      _overlayEntry?.markNeedsBuild();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    _overlayEntry?.markNeedsBuild();
    
    try {
      final supabase = ref.read(supabaseClientProvider);
      // Supabase ILIKE with OR
      final res = await supabase.from('customers').select('id, name, customer_id, mobile, consumer_number, village')
        .or('name.ilike.%$query%,customer_id.ilike.%$query%,mobile.ilike.%$query%,consumer_number.ilike.%$query%,village.ilike.%$query%')
        .limit(10);
        
      if (mounted) {
        setState(() {
          _results = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
        _overlayEntry?.markNeedsBuild();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _overlayEntry?.markNeedsBuild();
      }
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: MediaQuery.of(context).size.width - 32, // Assuming 16 padding on each side
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 60), // Below text field
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: _buildOverlayContent(),
              ),
            ),
          ),
        );
      }
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  Widget _buildOverlayContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_results.isEmpty && _searchController.text.trim().length >= 2) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No customers found.'),
      );
    }
    
    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final c = _results[index];
        return ListTile(
          title: Text(c['name'] ?? ''),
          subtitle: Text('${c['customer_id'] ?? ''} • ${c['mobile'] ?? ''} • ${c['village'] ?? ''}'),
          onTap: () {
            _searchController.text = c['name'];
            setState(() {
              _selectedCustomer = c;
              _results = [];
            });
            widget.onCustomerSelected(c['id']);
            _hideOverlay();
            _focusNode.unfocus();
          },
        );
      },
    );
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hideOverlay();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _searchController,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: 'Customer *',
          hintText: 'Search by Name, Mobile, ID...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _selectedCustomer != null 
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
        ),
        validator: (val) {
          if (val == null || val.isEmpty) return 'Required';
          if (_selectedCustomer == null) return 'Please select a valid customer from the list';
          return null;
        },
      ),
    );
  }
}
