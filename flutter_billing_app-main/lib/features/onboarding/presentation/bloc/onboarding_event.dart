part of 'onboarding_bloc.dart';

abstract class OnboardingEvent extends Equatable {
  const OnboardingEvent();
  @override
  List<Object> get props => [];
}

/// Fetches the list of business types from Supabase.
class LoadBusinessTypes extends OnboardingEvent {}

/// User selected a business type — persists it and prepares step 2.
class SelectBusinessType extends OnboardingEvent {
  final String businessTypeId;
  final String businessTypeName;

  const SelectBusinessType({
    required this.businessTypeId,
    required this.businessTypeName,
  });

  @override
  List<Object> get props => [businessTypeId, businessTypeName];
}

/// Fetches the starter catalog templates for the selected business type.
class LoadStarterCatalog extends OnboardingEvent {
  final String businessType;

  const LoadStarterCatalog(this.businessType);

  @override
  List<Object> get props => [businessType];
}

/// Toggles a template's selection on/off in the preview list.
class ToggleTemplateSelection extends OnboardingEvent {
  final String templateId;

  const ToggleTemplateSelection(this.templateId);

  @override
  List<Object> get props => [templateId];
}

/// User confirmed the starter catalog — bulk inserts products + inventory.
class ConfirmStarterCatalog extends OnboardingEvent {}
