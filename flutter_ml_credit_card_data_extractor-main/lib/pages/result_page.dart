import 'package:card_scanner/animation/fade_animation.dart';
import 'package:card_scanner/utils/card_input_formatter.dart';
import 'package:card_scanner/utils/month_year_picker.dart';
import 'package:card_scanner/widgets/credit_card_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class ResultPage extends StatefulWidget {
  final String cardNumber;
  final String expiryDate;

  const ResultPage({
    super.key,
    required this.cardNumber,
    required this.expiryDate,
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  late String cardNumber;
  late String expiryDate;

  static const int animateDelay = 450;

  @override
  void initState() {
    super.initState();
    cardNumber = widget.cardNumber;
    expiryDate = widget.expiryDate;
  }

  void onTapExpiryDate() async {
    final result = await showExpiryPicker(context, expiryDate);
    if (result != null) {
      setState(() => expiryDate = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back_ios,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(height: 5),
              FadeAnimation(
                delay: const Duration(milliseconds: 0),
                child: Hero(
                  tag: 'scanner',
                  child: Material(
                    type: MaterialType.transparency,
                    child: CreditCardWidget(
                      cardNumber: cardNumber,
                      expiryDate: expiryDate,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              FadeAnimation(
                delay: const Duration(milliseconds: animateDelay),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Card Number",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextFormField(
                      initialValue: cardNumber,
                      onChanged: (value) {
                        setState(() => cardNumber = value);
                      },
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(16),
                        CardNumberInputFormatter(),
                      ],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        hintText: "XXXX XXXX XXXX XXXX",
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              FadeAnimation(
                delay: const Duration(milliseconds: animateDelay + 50),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Expiry Date",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextFormField(
                      readOnly: true,
                      onTap: onTapExpiryDate,
                      controller: TextEditingController(text: expiryDate),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        hintText: "MM/YY",
                        suffixIcon: const Icon(Icons.calendar_month),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 50),

              FadeAnimation(
                delay: const Duration(milliseconds: animateDelay + 100),
                child: ElevatedButton(onPressed: () {}, child: Text("Submit")),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
