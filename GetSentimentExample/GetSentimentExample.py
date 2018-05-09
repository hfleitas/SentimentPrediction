import pandas as p
from microsoftml import rx_featurize, get_sentiment

# analyze_this = text

# Create the data
text_to_analyze = p.DataFrame(data=dict(Text=[
"These are not a normal stress reliever. First of all, they got sticky, hairy and dirty on the first day I received them. Second, they arrived with tiny wrinkles in their bodies and they were cold. Third, their paint started coming off. Fourth when they finally warmed up they started to stick together. Last, I thought they would be foam but, they are a sticky rubber. If these were not rubber, this review would not be so bad.",
"These are the cutest things ever!! Super fun to play with and the best part is that it lasts for a really long time. So far these have been thrown all over the place with so many of my friends asking to borrow them because they are so fun to play with. Super soft and squishy just the perfect toy for all ages."]))

# Get the sentiment scores
sentiment_scores = rx_featurize(
	data=text_to_analyze,
	ml_transforms=[get_sentiment(cols=dict(scores="Text"))])

# Lets translate the score to something more meaningful
sentiment_scores["Sentiment"] = sentiment_scores.scores.apply(
	lambda score: "Positive" if score > 0.6 else "Negative")
print(sentiment_scores)