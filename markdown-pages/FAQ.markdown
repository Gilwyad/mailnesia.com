#title Frequently Asked Questions
#description Frequently Asked Questions - now with answers! :)

<contents>

## What do I do if people are spamming my site ?

You should report the offending IP's and email addresses to
<http://stopforumspam.com> - their database is used to automatically
ban spammers from Mailnesia.

You should also consider using this service to ban spammers from your
website.

## Mailnesia.com is spamming me, how do I stop this?

Mailnesia.com is not spamming anyone as this is a receive-only
service, there are *no* outgoing emails.  If you see an e-mail with a
mailnesia.com **From:** header, that means absolutely nothing since
the sender can write *anything* in the e-mail From: header.  What
matters is the **Received:** header which is usually only seen when
you open the raw view of the email, as this contains the email servers
that actually sent the message.

## My website got numerous registrations with mailnesia.com addresses.  Are these bots or legitimate users?

It's your website, you should know your visitors and what they do
there!  Furthermore, it's your responsibility to make sure that
registration is not possible for bots!  (Use a captcha, for example <http://www.google.com/recaptcha>.)

## How to make the site forget my last opened mailbox?

You might not want the last viewed mailbox remembered by the site, as
it allows anyone who uses the same browser on the same machine after
you to have access to your emails.

To clear the last viewed mailbox <a href="/FAQ.html" onclick="$.cookie('mailbox','', { path: '/' })">click here</a>.  Alternatively you may find it easier to just click the [random mailbox](/?random=1;redirect=1) link so that an empty mailbox will be remembered.  Also if you are concerned about your privacy on a public machine then be sure to clear your browsing history in your browser's settings, and/or consider deleting your emails.

## I deleted an email, why is it still in my RSS reader?

After an email is deleted, it is no longer listed in the RSS feed.
However, some RSS readers (like Google Reader) store the contents of
the feed, and display the previously saved items along with the
current items.  

## How do I create a mailbox?

Creating a mailbox is fully automatic, there is no "registration"
here.  You just have to send an email to any address@mailnesia.com, it
will be "created" automatically!

## So anyone can read my mail?

Yes, since there is no password.  So don't choose a simple name, try
to make it unique.  You can also set an alias to prevent others from
opening your mailbox.  Check it out on the [features](/features.html) page (and the next
question).

## What's this alias stuff anyway?

Let's say you choose the mailbox *myef* and the alias *frain*.  Open
<http://mailnesia.com/mailbox/myef>, and enter 'frain' in the alias
textbox, click OK or press enter.  If it was successful, then mail
sent to both myef@mailnesia.com and frain@mailnesia.com can be read at
<http://mailnesia.com/mailbox/myef>, and CANNOT be read at
<http://mailnesia.com/mailbox/frain>.  So you can give out
*frain@mailnesia.com* to the whole Internet, and nobody can read your
mail but you!

Unless of course, if you choose a too simple mailbox like 'a', which can be guessed.

## How do I send an email from mailnesia.com ?

You can't, there is no such feature.

## How can I delete an email?

There is a delete button above the opened email.

Check out "deleting messages" @ [the features page](features.html#delete).

## Are there any more domains ?

Yes, there are other domains beside @mailnesia.com that can be used
for receiving emails.  Check out the [features](features.html#domain) page!

## Why didn't my registration complete automatically ?

Mailnesia won't click on *all* links, only registration-looking ones, which contain keywords like **register**, **confirm**, **verify** etc.  So if an activation link doesn't contain any such keywords, for example http://soundcloud.com/emails/5ef6e26f, then it will not be clicked automatically.  If this happens to you then [send me](contact.html) this link so I can add it to the keywords list.  

Also, there are sites where you have to do something on the activation
page, like fill out a captcha or press a button - you will have to do
these manually.  For example at twitter.com you have to be logged in
to confirm an account, therefore automatic activation is not possible.

My blog post about this: <http://blog.mailnesia.com/url-clicker-changes>.

## What about registrations with one-time links?

Some sites require manual steps (like choosing a password or logging
in) with registration links that can only be used once. If you find
such a site then please [send me](contact.html) the activation link or website address
so I can add it to the exceptions list, to prevent the system from
automatically visiting these links.

## What does nesia mean?

It's from Greek: νῆσος/nēsos/nesia: means islands.

## What's up with the name?

 1. like Polynesia means 'many islands', Melanesia means 'islands of the black-skinned people',  Micronesia means 'small islands', Mailnesia means 'mail islands'.
 2. think of Amnesia, as in, make a fake address, register, and then forget about it.
