// jQuery Cookie Plugin
// https://github.com/carhartl/jquery-cookie
//
// Copyright 2011, Klaus Hartl
// Dual licensed under the MIT or GPL Version 2 licenses.
// http://www.opensource.org/licenses/mit-license.php
// http://www.opensource.org/licenses/GPL-2.0

(function($) {
    $.cookie = function(key, value, options) {

        // key and at least value given, set cookie...
        if (arguments.length > 1 && (!/Object/.test(Object.prototype.toString.call(value)) || value === null || value === undefined)) {
            options = $.extend({}, options);

            if (value === null || value === undefined) {
                options.expires = -1;
            }

            if (typeof options.expires === 'number') {
                var days = options.expires, t = options.expires = new Date();
                t.setDate(t.getDate() + days);
            }

            value = String(value);

            return (document.cookie = [
                encodeURIComponent(key), '=', options.raw ? value : encodeURIComponent(value),
                options.expires ? '; expires=' + options.expires.toUTCString() : '', // use expires attribute, max-age is not supported by IE
                options.path    ? '; path=' + options.path : '',
                options.domain  ? '; domain=' + options.domain : '',
                options.secure  ? '; secure' : ''
            ].join(''));
        }

        // key and possibly options given, get cookie...
        options = value || {};
        var decode = options.raw ? function(s) { return s; } : decodeURIComponent;

        var pairs = document.cookie.split('; ');
        for (var i = 0, pair; pair = pairs[i] && pairs[i].split('='); i++) {
            if (decode(pair[0]) === key) return decode(pair[1] || ''); // IE saves cookies with empty string as "c; ", e.g. without "=" as opposed to EOMB, thus pair[1] may be undefined
        }
        return null;
    };
})(jQuery);

!function( $ ){

  "use strict"

  function activate ( element, container ) {
    container
      .find('> .active')
      .removeClass('active')
      .find('> .dropdown-menu > .active')
      .removeClass('active')

    element.addClass('active')

    if ( element.parent('.dropdown-menu') ) {
      element.closest('li.dropdown').addClass('active')
    }
  }

  function tab( e ) {
    var $this = $(this)
      , $ul = $this.closest('ul:not(.dropdown-menu)')
      , href = $this.attr('href')
      , previous
      , $href

    if ( /^#\w+/.test(href) ) {
      e.preventDefault()

      if ( $this.parent('li').hasClass('active') ) {
        return
      }

      previous = $ul.find('.active a').last()[0]
      $href = $(href)

      activate($this.parent('li'), $ul)
      activate($href, $href.parent())

      $this.trigger({
        type: 'change'
      , relatedTarget: previous
      })
    }
  }


  $.fn.tabs = $.fn.pills = function ( selector ) {
    return this.each(function () {
      $(this).delegate(selector || '.tabs li > a, .pills > li > a', 'click', tab)
    })
  }

  $(document).ready(function () {
    $('body').tabs('ul[data-tabs] li > a, ul[data-pills] > li > a')
  })

}( window.jQuery || window.ender );



function asyncjsload__(src__) {
        var element__ = document.createElement('script');
        var first__ = document.getElementsByTagName('script')[0];
        element__.type = 'text/javascript';
        element__.async = true;
        element__.src = src__;
        first__.parentNode.insertBefore(element__, first__);
};

var _gaq = _gaq || [];
_gaq.push(['_setAccount', 'UA-17894100-2']);
_gaq.push(['_trackPageview']);

function jsloadertimeout__(){
    asyncjsload__("http://c.supportchamp.com/core.js?d=d0f5fee4845a0d53");
    asyncjsload__("http://www.google-analytics.com/ga.js");
    asyncjsload__("https://apis.google.com/js/plusone.js");
}

if (window.location.host == "mailnesia.com") {
    setTimeout(jsloadertimeout__, 1); // strictly advanced tech!
}

if (/^http:\/\/[^\/]+(\/[a-z][a-z])?\/?$/.test(window.location.href) ) {
    window.onload = function() {
        $('#mailbox').focus();
    }
}

var d=new Date();
$.cookie('tz', d.getTimezoneOffset(), { path: '/mailbox' } );

function confirmDeleteEmail() {

    $("#delete_email").html("<i>Are you sure you want to delete this email?</i><input type='button' class='btn danger' onclick=\'deleteEmail()\' value='YES delete it !'>");
}

function confirmEmptyMailbox() {

    $("#empty_mailbox").html("<i>Are you sure you want to delete all emails in this mailbox?</i><input type='button' class='btn danger' onclick=\'wipeMailbox()\' value='YES delete them !'>");
}


function deleteEmail() {

    $.ajax({
        url: window.location.href,
        type: "POST",
        data: {"delete": 1},
        success: function(response) {
            $("#delete_email").html(response);
        },
        error: function(xhr) {
            $("#delete_email").html( '<span class="alert-message error">HTTP ERROR ' + xhr.status + '</span>');
        }
    });

}


function wipeMailbox() {

    $.ajax({
        url: window.location.href,
        type: "POST",
        data: {"delete": 1},
        success: function(response) {
            $("#empty_mailbox").html(response);
        },
        error: function(xhr) {
            $("#empty_mailbox").html( '<span class="alert-message error">HTTP ERROR ' + xhr.status + '</span>');
        }
    });

}

// only poll when a mailbox is opened
if (/\/mailbox\/[^\/]+\/?$/.test(window.location.href) ) {

     // and only on the first page
    var pageNumber = /p=([0-9]+)/.exec(window.location.href);
    if ( pageNumber == null || ! ( pageNumber[1] > 0 )) {
        setInterval ( function () {

            var jquery_selector = "table.email>tbody>tr:first-child";
            var most_recent_mail_id = $(jquery_selector).attr('id') || 1;

            $.get(window.location.href, {
                newerthan: most_recent_mail_id,
                noheadernofooter: 1},
                   function(data, textStatus, xhr) {
                       if (xhr.status == 200)
                       {
                           if ( most_recent_mail_id == 1 )
                           {
                               $("h2.emails").remove();
                               $("table.email>tbody").html(data);
                           }
                           else
                           {
                               $(data).insertBefore(jquery_selector);
                           }
                       }
                   }
                  );
        }, 60000 );
    }
}


function openEmail(mailbox,id) {
    var emailbodyID = '#emailbody_'+id;

    if ( $(emailbodyID).length ) {
        if (! $(emailbodyID + ' td div.alert-message.error').length)
        {
            //hide/show
            if ($(emailbodyID).is(':visible')) {
                $(emailbodyID).hide('fast');
                $("tr#" + id).addClass("even").removeClass("odd");
            }
            else if ($(emailbodyID).is(':hidden')) {
                $(emailbodyID).show('fast');
                $("tr#" + id).addClass("odd").removeClass("even");
            }
            return;
        }
    }
    else
    {
        $('<tr id="emailbody_'+id+'"><td style="padding: 0;" colspan="5"><p>LOADING<p></td></tr>').insertAfter('#'+id);
        $("tr#" + id).addClass("odd");
    }



    $.ajax({
     url: '/mailbox/' + mailbox + '/' + id + '?noheadernofooter=ajax',
     success: function(response) {
         $(emailbodyID+' td').html(response);
     },
     error: function(xhr) {
         $(emailbodyID+' td').html('<div class="alert-message error">Error!  HTTP ' + xhr.status + ' ' + xhr.statusText + '</div>');
     }
    });

    
}


// autopager, only in mailbox view ( no matter which page ) and there is pagination
if (/\/mailbox\/[^\/]+\/?(?:\?.*)*$/.test(window.location.href) && $( 'div.pagination' ).length ) {

    var currentPage = /p=([0-9]+)/.exec(window.location.href);
    var nextPage = ( currentPage == null ) ? 1 : ++currentPage[1] ;
    var autoPager = function () {
        var scrolledPixels = $(document).scrollTop();
        var documentHeight = $(document).height();
        var windowHeight   = $(window).height();

        if ( documentHeight - scrolledPixels - windowHeight < 500 )
        {
            // load next page
            var jquerySelector = "table.email>tbody>tr:last";
            var mailbox = /\/mailbox\/([^\/\?]+)/.exec(window.location.href);
            if ( ! mailbox[1] )
            {
                // error, stop 
                clearInterval ( intervalID );
                return;
            }

            $.ajax({
                url: '/mailbox/' + mailbox[1] + '?noheadernofooter=autopager&p=' + nextPage,
                success: function(response) {
                    if ( response.length == 0 )
                    {
                        // no more pages
                        clearInterval ( intervalID );
                    }
                    else
                    {
                        $( jquerySelector ).after(response);
                        nextPage++;
                    }
                },
                error: function(xhr) {
                    $( jquerySelector ).after('<tr><td colspan="5"><div class="alert-message error">Error!  HTTP ' + xhr.status + ' ' + xhr.statusText + '</div></td></tr>');
                }
            });
            
        }
    }

    var intervalID = setInterval ( function() { autoPager() }, 1000 );
}


function setLanguage (lang, translation_complete) {

    $.cookie('language',lang, { path: '/' });

    var mailbox = /\/mailbox\/.+/.exec(window.location.href);

    if ( mailbox )
    {
        // /mailbox/
        window.location.reload(true);
        return false;
    }
    else
    {
        if ( lang == 'en' || ! translation_complete )
        {
            window.location.href = '/';
        }
        else
        {
            window.location.href = '/' + lang + '/';
        }
        return false;
    }
}

function toggleClicker() {

    $.ajax({
        url: window.location.href + "/clicker",
        type: "POST",
        data: {"set_clicker": $('#clicker_checkbox').is(':checked') ? 1 : 0},
        success: function(response) {
            $("#clicker-status").html(response);
        },
        error: function(xhr) {
            $("#clicker-status").html( '<span class="alert-message error">' + get_error_message(xhr) + '</span>');
        }
    });


}

// when page loading done, attach function to 'add new alias form' button, and fire bind submit event
$(document).ready(function () {

    // add new alias form
    $('#add_new_alias_form').bind('click', function (event) {
        var mailbox = $.cookie('mailbox');
        var form = '<form method="post" action="#" onsubmit="return false;"><input type="text" name="alias" tabindex="10" size="20" maxlength="30" class="xlarge" title="alias"><input type="hidden" name="mailbox" value="' +mailbox+ '"><input type="hidden" name="remove_alias" value=""><input type="submit" name="ok" value="Ok" class="btn primary"><input type="submit" name="delete" value="Delete" class="btn danger" style="display: none;" ></form>';

        $("ol").append('<li class="form"><div class="alias_result"></div><div class="alias_form">'
                       +form+
                       '</div></li>');

        // bind the last ok button, that was just inserted
        bind_submit_ok('li:last>div>form');
        // bind the last delete button, that was just inserted
        bind_submit_delete('li:last>div>form');
    });

    // bind all ok buttons on page load
    bind_submit_ok('li>div>form');

    // bind all delete buttons on page load to the delete alias javascript function
    bind_submit_delete('li>div>form');

});

// bind alias forms submit button to ajax function
function bind_submit_ok (selector) {

    $(selector).bind('submit', function() { return false; });
    $(selector + '>input[name="ok"]').bind('click', function (event) {

        var mailbox      = $(this).siblings('input[name="mailbox"]').val() ;
        var alias        = $(this).siblings('input[name="alias"]').val() ;
        var remove_alias = $(this).siblings('input[name="remove_alias"]').val() ;

        if ( ! (alias && mailbox) ) { return false; }

        if ( remove_alias ) {
            // modify alias

            if ( alias == remove_alias ) { return false; }

            $.ajax({
                url: "/settings/" + mailbox + "/alias/modify",
                type: "POST",
                data: {
                    "alias": alias,
                    "remove_alias": remove_alias
                },
                success: function(response) {
                    $(event.target).parent().parent().prev("div").html('<span class="alert-message success">' + response + '</span>');
                    // save the alias in the form's "remove_alias" hidden field
                    $(event.target).parent().find('input[name="remove_alias"]').val(alias);
                },
                error: function(xhr) {
                    $(event.target).parent().parent().prev("div").html('<span class="alert-message error">' + get_error_message(xhr) + '</span>');
                }
            });

        }
        else
        {
            // set new alias

            $.ajax({
                url: "/settings/" + mailbox + "/alias/set",
                type: "POST",
                data: {"alias": alias},
                success: function(response) {
                    //            $(this).parent().find("div").html(response);
                    //            $('form').next('div').html(response);
                    //            alert(response)
                    $(event.target).parent().parent().prev("div").html('<span class="alert-message success">' + response + '</span>');
                    // save the alias in the form's "remove_alias" hidden field
                    $(event.target).parent().find('input[name="remove_alias"]').val(alias);
                    // show delete button
                    $(event.target).parent().find('input[name="delete"]').show();
                },
                error: function(xhr) {
                    $(event.target).parent().parent().prev("div").html('<span class="alert-message error">' + get_error_message(xhr) + '</span>');
                }
            });
        }

    });
}



// bind alias forms submit button to ajax function
function bind_submit_delete (selector) {

    $(selector).bind('submit', function() { return false; });
    $(selector + '>input[name="delete"]').bind('click', function (event) {

        var mailbox      = $(this).siblings('input[name="mailbox"]').val() ;
        var remove_alias = $(this).siblings('input[name="remove_alias"]').val() ;


        if ( ! (mailbox && remove_alias) ) { return false; }

        $.ajax({
            url: "/settings/" + mailbox + "/alias/remove",
            type: "POST",
            data: {"remove_alias": remove_alias},
            success: function(response) {
                $(event.target).parent().parent().prev("div").html('<span class="alert-message warning">' + response);//fixme /span
                // delete the alias from the form's "remove_alias" hidden field
                $(event.target).parent().find('input[name="remove_alias"]').val("");
                // delete the alias from the form's text field
                $(event.target).parent().find('input[name="alias"]').val("");
                // hide delete button
                $(event.target).parent().find('input[name="delete"]').hide();

            },
            error: function(xhr) {
//                $(event.target).parent().next("div").html('<span class="alert-message error">' + get_error_message(xhr) + '</span>');
                $(event.target).parent().parent().prev("div").html('<span class="alert-message error">' + get_error_message(xhr) + '</span>');
            }
        });

    });
}


function get_error_message (x) {
    if ( x.status >= 502 && x.status <= 504 )
    {
        return "Service down - please try again in a few seconds";
    }
    else
    {
        return x.responseText || x.statusText;
    }
}
