// Learning example only: this does not start a server or change database stock.
const breadName: string = "Butter Sugar Bun";
const quantity: number = 3;
const unitPrice: number = 6;

function calculateSubtotal(quantity: number, unitPrice: number): number {
  return quantity * unitPrice;
}

const subtotal: number = calculateSubtotal(quantity, unitPrice);
console.log(`${breadName}: ${quantity} buns, subtotal RM${subtotal.toFixed(2)}`);

