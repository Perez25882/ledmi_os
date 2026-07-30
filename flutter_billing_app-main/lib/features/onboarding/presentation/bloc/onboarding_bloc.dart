import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/supabase/session_manager.dart';
import '../../data/services/onboarding_service.dart';

part 'onboarding_event.dart';
part 'onboarding_state.dart';

class OnboardingBloc extends Bloc<OnboardingEvent, OnboardingState> {
  final OnboardingService _service;

  OnboardingService get service => _service;

  OnboardingBloc({required OnboardingService service})
      : _service = service,
        super(const OnboardingState()) {
    on<LoadBusinessTypes>(_onLoadBusinessTypes);
    on<SelectBusinessType>(_onSelectBusinessType);
    on<LoadStarterCatalog>(_onLoadStarterCatalog);
    on<ToggleTemplateSelection>(_onToggleTemplateSelection);
    on<ConfirmStarterCatalog>(_onConfirmStarterCatalog);
  }

  Future<void> _onLoadBusinessTypes(
    LoadBusinessTypes event,
    Emitter<OnboardingState> emit,
  ) async {
    emit(state.copyWith(
      status: OnboardingStatus.loading,
      step: OnboardingStep.businessType,
      clearError: true,
    ));
    try {
      final types = await _service.getBusinessTypes();
      emit(state.copyWith(
        status: OnboardingStatus.success,
        businessTypes: types,
      ));
    } catch (e) {
      emit(state.copyWith(status: OnboardingStatus.error, error: e.toString()));
    }
  }

  Future<void> _onSelectBusinessType(
    SelectBusinessType event,
    Emitter<OnboardingState> emit,
  ) async {
    final businessId = SessionManager.businessId;
    if (businessId == null) {
      emit(state.copyWith(
        status: OnboardingStatus.error,
        error: 'No active business session',
      ));
      return;
    }

    emit(state.copyWith(
      status: OnboardingStatus.loading,
      selectedBusinessTypeId: event.businessTypeId,
      selectedBusinessTypeName: event.businessTypeName,
      clearError: true,
    ));

    try {
      await _service.saveBusinessType(
        businessId: businessId,
        businessType: event.businessTypeId,
      );
      emit(state.copyWith(
        status: OnboardingStatus.success,
        step: OnboardingStep.starterCatalog,
      ));
      add(LoadStarterCatalog(event.businessTypeId));
    } catch (e) {
      emit(state.copyWith(
        status: OnboardingStatus.error,
        error: e.toString(),
      ));
    }
  }

  Future<void> _onLoadStarterCatalog(
    LoadStarterCatalog event,
    Emitter<OnboardingState> emit,
  ) async {
    emit(state.copyWith(
      status: OnboardingStatus.loading,
      clearError: true,
    ));
    try {
      final templates = await _service.getStarterCatalog(event.businessType);
      emit(state.copyWith(
        status: OnboardingStatus.success,
        catalogTemplates: templates,
        deselectedTemplateIds: const {},
      ));
    } catch (e) {
      emit(state.copyWith(
        status: OnboardingStatus.error,
        error: e.toString(),
      ));
    }
  }

  void _onToggleTemplateSelection(
    ToggleTemplateSelection event,
    Emitter<OnboardingState> emit,
  ) {
    final current = Set<String>.from(state.deselectedTemplateIds);
    if (current.contains(event.templateId)) {
      current.remove(event.templateId);
    } else {
      current.add(event.templateId);
    }
    emit(state.copyWith(deselectedTemplateIds: current));
  }

  Future<void> _onConfirmStarterCatalog(
    ConfirmStarterCatalog event,
    Emitter<OnboardingState> emit,
  ) async {
    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;
    if (businessId == null || branchId == null) {
      emit(state.copyWith(
        status: OnboardingStatus.error,
        error: 'No active business/branch session',
      ));
      return;
    }

    emit(state.copyWith(status: OnboardingStatus.loading, clearError: true));

    try {
      await _service.loadStarterCatalogIntoProducts(
        businessId: businessId,
        branchId: branchId,
        selectedTemplates: state.selectedTemplates,
      );
      emit(state.copyWith(
        status: OnboardingStatus.success,
        step: OnboardingStep.shelfScan,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: OnboardingStatus.error,
        error: e.toString(),
      ));
    }
  }
}
