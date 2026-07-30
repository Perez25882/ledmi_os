part of 'onboarding_bloc.dart';

enum OnboardingStep { initial, businessType, starterCatalog, shelfScan, done }

enum OnboardingStatus { idle, loading, success, error }

class OnboardingState extends Equatable {
  final OnboardingStep step;
  final OnboardingStatus status;
  final List<BusinessType> businessTypes;
  final String? selectedBusinessTypeId;
  final String? selectedBusinessTypeName;
  final List<StarterCatalogTemplate> catalogTemplates;
  final Set<String> deselectedTemplateIds;
  final String? error;

  const OnboardingState({
    this.step = OnboardingStep.initial,
    this.status = OnboardingStatus.idle,
    this.businessTypes = const [],
    this.selectedBusinessTypeId,
    this.selectedBusinessTypeName,
    this.catalogTemplates = const [],
    this.deselectedTemplateIds = const {},
    this.error,
  });

  /// Templates the user has kept selected (not toggled off).
  List<StarterCatalogTemplate> get selectedTemplates =>
      catalogTemplates
          .where((t) => !deselectedTemplateIds.contains(t.id))
          .toList();

  OnboardingState copyWith({
    OnboardingStep? step,
    OnboardingStatus? status,
    List<BusinessType>? businessTypes,
    String? selectedBusinessTypeId,
    String? selectedBusinessTypeName,
    List<StarterCatalogTemplate>? catalogTemplates,
    Set<String>? deselectedTemplateIds,
    String? error,
    bool clearError = false,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      status: status ?? this.status,
      businessTypes: businessTypes ?? this.businessTypes,
      selectedBusinessTypeId:
          selectedBusinessTypeId ?? this.selectedBusinessTypeId,
      selectedBusinessTypeName:
          selectedBusinessTypeName ?? this.selectedBusinessTypeName,
      catalogTemplates: catalogTemplates ?? this.catalogTemplates,
      deselectedTemplateIds:
          deselectedTemplateIds ?? this.deselectedTemplateIds,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
        step,
        status,
        businessTypes,
        selectedBusinessTypeId,
        selectedBusinessTypeName,
        catalogTemplates,
        deselectedTemplateIds,
        error,
      ];
}
