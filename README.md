# ECS191-HW

# Build Instructions:

1. Go to [Finnhub](https://finnhub.io/) and get a free API key
2. In SmartStock/Config/, create a copy of "Secrets.example.xcconfig" and name it "Secrets.xcconfig"
3. In line 4, replace "your_finnhub_api_key_here" with the API key from Finnhub
4. Open SmartStock/SmartStock.xcodeproj in Xcode and build+run

# Main Feature Usage

## Watchlist 
1. Click the magnifying to search for a financial asset
2. Click the plus button to add to watchlist
3. Click on the asset in the list to view details
4. Click and drag across the graph to see the price at different at different times; Click the buttons above the graph to change time intervals.
5. Optionally, enable simple indicators at the bottom of the screen

## My Positions
1. From the watchlist view, click the My Positions button at the bottom of the screen (or Edit > My Positions)
2. Click the plus button in the top right to search for an asset that you own
3. Click the symbol and enter purchase details (date, price, # of shares/dollar amount)
4. Click positions that have been added to the My Positions view to see the price history of your position
