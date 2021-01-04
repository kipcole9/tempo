---
layout: post
categories: [cldr, i18n, l10n]
title: Every Application is Localised
---

Start-ups and established businesses alike aim to engage with their customers, create a trusted relationship and in many cases aim to be a destination for a target audience. Common doctrine says that deeper engagement with customers has a direct impact on revenue and profit.

[Forbes](https://www.forbes.com/sites/blakemorgan/2019/09/24/50-stats-that-prove-the-value-of-customer-experience/?sh=274559da4ef2) suggests businesses with a customer experience mind-set outperform other businesses by 80%.

> Companies that lead in customer experience outperform laggards by nearly 80%. 84% of companies that work to improve their customer experience report an increase in their revenue.

Given that presenting and accepting input from users in formats that that reflect their individual preferences (often based upon cultural factors) is an important part of customer experience, why aren't all developers considering localization as part of their application strategy?  Larger application vendors certainly do, but in the broader developer community it seems to be less common.

The conversation often goes "*I need to ship, I'll localise later*". However since all information is being presented in a some language, script and format its reasonable to say that all applications are localised. Even if they present content and accept input in only one format.

Another argument goes that the US is the largest online economy and the most open market and therefore developing for US consumers first makes the most economic sense. However if we compare the revenue for online retailers for Black Friday and Cyber Monday in the US to Singles Day in China we find that Singles Day is [more than double the size of Black Friday and Cyber Monday combined](https://www.techradar.com/sg/news/singles-day-officially-bigger-than-black-friday-and-cyber-monday-combined).

In Indonesia, a country of 294m people (ie similar in size to the USA), [90% of people between the ages of 16 to 64 purchased goods online in the 12 months to September 2019](https://datareportal.com/reports/digital-2019-ecommerce-in-indonesia).

> GlobalWebIndex reports that Indonesia has the highest rate of ecommerce use of any country in the world, with 90 percent of the country’s internet users between the ages of 16 and 64 reporting that they already buy products and services online.

It's a faster growing economy [averaging over 5% annual growth from 2000 to 2020](https://tradingeconomics.com/indonesia/gdp-growth-annual) and it has an investment-oriented market economy. For the same period of time, the US economy has been growing at [an aveage of 2%](https://tradingeconomics.com/united-states/gdp-growth-annual).

These are simple examples intended only to illustrate that by not thinking about global audiences, application developers are potentially alienating potential customers simply because they aren't respecting the customers preferences when it comes to presentation and input.

### Commonly Used Localisation libraries

In conversation with developers, the biggest barrier has been the assumption that localising is complex, difficult and time-consuming. Getting to market fast has a higher priority.

On the other hand, [Elixir Forum](https://elixirforum.com) has several questions that ask "*how do I format a number with grouping*" or "*how to I format a money amount*" suggesting that there is a desire to format and allow input in a language or region specific way.

Perhaps the primary challenge is that conventional tooling to support localisation is feature rich but also complex. The most common library is [libicu](http://site.icu-project.org/home) available in Java and C/C++ forms. For the Ruby community [TwitterCLDR](https://blog.twitter.com/engineering/en_us/a/2012/twittercldr-improving-internationalization-support-in-ruby.html) is popular and there is a [javascript](https://github.com/twitter/twitter-cldr-js) version too.

In modern web browsers, the [Int](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl) object providers formatting capabilities although browser UI components do not typically support locale-specific formatting or input.

For the Elixir community, [ex_cldr](https://hex.pm/packages/ex_cldr) (by the author) provides support for the majority of the localisation data defined by [CLDR](https://cldr.unicode.org) and is designed to make it easy to localise common data formats such as numbers, dates, times and units of measure and lists.

### Every application is localised

Every application is localised insofar as decisions are made by the developer for formatting output and consuming input from a user.  If it can be as easy to localise input for many locales as it is to localise for one, then why not localise?  The next post looks at how easy it is to localise with [ex_cldr](https://hex.pm/packages/ex_cldr).











