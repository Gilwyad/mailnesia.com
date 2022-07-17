#!/usr/bin/python
# -*- coding: utf-8 -*-

import os
import gspread                  # https://github.com/burnash/gspread
from oauth2client.service_account import ServiceAccountCredentials
import codecs

script_dir = os.path.dirname(os.path.realpath(__file__))
scope = ['https://spreadsheets.google.com/feeds']

# Obtain OAuth2 credentials from Google Developers Console (https://gspread.readthedocs.io/en/latest/oauth2.html)
credentials = ServiceAccountCredentials.from_json_keyfile_name(script_dir + '/../lib/Mailnesia/mailnesia-private.json', scope)

gs = gspread.authorize(credentials)

# open translation spreadsheet at https://docs.google.com/spreadsheets/d/1Qd6QHFWXmD-Cyz3nV3Q0DwKj3b5wkwTflcS6PKIWkoo
spreadsheet = gs.open_by_key('1Qd6QHFWXmD-Cyz3nV3Q0DwKj3b5wkwTflcS6PKIWkoo')



def save_worksheet (name: str):
    """
    Name should be the name of the worksheet, "mailnesia_translation" or "main page" or "features page"
    """
    worksheet = spreadsheet.worksheet(name)
    list_of_lists = worksheet.get_all_values()

    tsv = ""                    # variable for storing the whole worksheet, tab separated

    for line in list_of_lists:
        for position, cell in enumerate(line):
            tsv = tsv + cell.replace("\n", " ") # ignore newlines inside cells
            if (position < len(line)-1):  # for all items except the last
                tsv = tsv + "\t"          # separate with tab
        tsv = tsv + "\n"                  # add newline


    # open .tsv for writing
    with codecs.open( script_dir + '/../translation/' + 'mailnesia_translation - ' + name + '.tsv', encoding='utf-8', mode='w') as f_translation:
        f_translation.write(tsv)


save_worksheet("mailnesia_translation")
save_worksheet("main page")
save_worksheet("features page")
