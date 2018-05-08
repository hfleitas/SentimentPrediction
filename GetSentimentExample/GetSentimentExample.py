import pandas as p
from microsoftml import rx_featurize, get_sentiment

# analyze_this = text

# Create the data
text_to_analyze = p.DataFrame(data=dict(Text=[
"How many times do I have try this?.",
"Bottom line is that it works on ML but not on SQL."]))

# Get the sentiment scores
sentiment_scores = rx_featurize(
	data=text_to_analyze,
	ml_transforms=[get_sentiment(cols=dict(scores="Text"))])

# Lets translate the score to something more meaningful
sentiment_scores["Sentiment"] = sentiment_scores.scores.apply(
	lambda score: "Positive" if score > 0.6 else "Negative")
print(sentiment_scores)