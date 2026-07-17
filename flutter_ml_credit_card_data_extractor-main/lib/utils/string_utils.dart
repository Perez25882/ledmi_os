class StringUtils {
  static String formatCardNumber(String cardNumber) {
    return cardNumber.replaceAllMapped(
      RegExp(r'\B(?=(\d{4})+(?!\d))'),
      (match) => ' ',
    );
  }

  static String formatExpiryDate(String date) {
    final parts = date.split(RegExp(r'[\/\-]'));
    if (parts.length != 2) {
      return date;
    }

    String month = parts[0];
    String year = parts[1];

    if (year.length == 4) {
      year = year.substring(2);
    }

    return "$month/$year";
  }
}
