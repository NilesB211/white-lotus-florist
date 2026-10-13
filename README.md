# White Lotus Florist · Bouquet Builder

Customers pick up to 4 of today's flowers, see three bouquet styles made from their picks with prices, and send an order. The owner updates flowers, photos and every price from her phone.

- **Customer page:** https://nilesb211.github.io/white-lotus-florist/
- **Owner dashboard:** https://nilesb211.github.io/white-lotus-florist/owner.html

## How it works
- `index.html`: the customer page. No sign-in needed.
- `owner.html`: the owner dashboard, protected by a passcode.
- `assets/`: shared styles, data access and the bouquet preview drawing.
- `supabase/setup.sql`: the database setup (already run on the "Flower Shop Bouquets" Supabase project).

Orders are saved in the database and appear in the dashboard's **Orders** tab. They are also emailed to the order email (info@wlflorist.com) through FormSubmit. The **first** order triggers a one-time "Activate form" email from FormSubmit to that address; click the link in it, or later orders won't be emailed (they still appear in the dashboard).

Price shown to customers = stems × each flower's per-stem price + the style price, rounded up to the dollar.
