import 'package:get/get.dart';

class InvoiceController extends GetxController {
  var invoices = <Invoice>[].obs;

  void addInvoice(Invoice invoice) {
    invoices.add(invoice);
  }

  void removeInvoice(Invoice invoice) {
    invoices.remove(invoice);
  }

  List<Invoice> getInvoices() {
    return invoices;
  }
}  

class Invoice {
  String id;
  double amount;
  String description;

  Invoice({required this.id, required this.amount, required this.description});
}