import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/service_locator.dart' as di;
import '../bloc/onboarding_bloc.dart';

/// Wraps all onboarding routes with a shared [OnboardingBloc] instance and a
/// [BlocListener] that navigates between steps as the bloc state evolves.
///
/// The bloc is created once per onboarding flow so that the selected business
/// type and starter-catalog choices persist across the three pages.
class OnboardingWrapper extends StatelessWidget {
  final Widget child;

  const OnboardingWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OnboardingBloc>(
      create: (_) => di.sl<OnboardingBloc>(),
      child: BlocListener<OnboardingBloc, OnboardingState>(
        listenWhen: (previous, current) => previous.step != current.step,
        listener: (context, state) {
          switch (state.step) {
            case OnboardingStep.starterCatalog:
              context.go('/onboarding/starter-catalog');
            case OnboardingStep.shelfScan:
              context.go('/onboarding/shelf-scan');
            case OnboardingStep.done:
              context.go('/');
            case OnboardingStep.businessType:
            case OnboardingStep.initial:
              break;
          }
        },
        child: child,
      ),
    );
  }
}
